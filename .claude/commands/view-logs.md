Show recent Azure production logs for the continuation app.

## Usage

`/view-logs` — show the last 50 request log lines
`/view-logs <n>` — show the last n request log lines
`/view-logs errors` — show only 4xx/5xx responses
`/view-logs slow` — show requests that took over 1000ms
`/view-logs follow` — tail live logs (streams until interrupted)

## What to do

The `az monitor log-analytics query` CLI extension is broken — use `az rest` to hit the Log Analytics API directly. Fetch the workspace ID first:

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group continuation-rg \
  --workspace-name continuation-logs \
  --query customerId -o tsv)
```

### follow

```bash
az containerapp logs show \
  --name continuation \
  --resource-group continuation-rg \
  --follow
```

### errors (4xx/5xx from Rails request logs)

```bash
az rest --method POST \
  --url "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  --headers "Content-Type=application/json" \
  --body "{\"query\": \"ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'continuation' | extend log = parse_json(Log_s) | where toint(log.status) >= 400 and isnotempty(log.controller) | project TimeGenerated, status=log.status, method=log.method, path=log.path, duration=log.duration, controller=log.controller, exception=log.exception | order by TimeGenerated desc | limit 50\"}" \
  --resource "https://api.loganalytics.io" \
  -o json
```

### slow (requests over 1000ms)

```bash
az rest --method POST \
  --url "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  --headers "Content-Type=application/json" \
  --body "{\"query\": \"ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'continuation' | extend log = parse_json(Log_s) | where todouble(log.duration) > 1000 and isnotempty(log.controller) | project TimeGenerated, duration=log.duration, method=log.method, path=log.path, controller=log.controller, action=log.action | order by TimeGenerated desc | limit 50\"}" \
  --resource "https://api.loganalytics.io" \
  -o json
```

### default (last N lines, Rails request logs only)

Replace `<N>` with the argument or 50:

```bash
az rest --method POST \
  --url "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  --headers "Content-Type=application/json" \
  --body "{\"query\": \"ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'continuation' | extend log = parse_json(Log_s) | where isnotempty(log.controller) | project TimeGenerated, status=log.status, method=log.method, path=log.path, duration=log.duration, controller=log.controller | order by TimeGenerated desc | limit <N>\"}" \
  --resource "https://api.loganalytics.io" \
  -o json
```

Parse and print the results in a readable table using Python:

```bash
... | python3 -c "
import json, sys
data = json.load(sys.stdin)
rows = data['tables'][0]['rows']
cols = [c['name'] for c in data['tables'][0]['columns']]
print('  '.join(f'{c:<30}' if i == 0 else f'{c:<12}' for i, c in enumerate(cols)))
print('-' * 100)
for r in rows:
    print('  '.join(f'{str(v or \"\"):<30}' if i == 0 else f'{str(v or \"\"):<12}' for i, v in enumerate(r)))
"
```

If the query returns no rows, note that:
- Logs may take a few minutes to appear after the app first receives traffic
- The `isnotempty(log.controller)` filter selects Rails lograge lines only — remove it to also see Thruster proxy logs and Puma startup messages
