Show recent Azure production logs for the continuation app.

## Usage

`/view-logs` — show the last 50 request log lines
`/view-logs <n>` — show the last n request log lines
`/view-logs errors` — show only 4xx/5xx responses
`/view-logs slow` — show requests that took over 1000ms
`/view-logs follow` — tail live logs (streams until interrupted)

## What to do

Fetch the workspace ID first (needed for all Log Analytics queries):

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

### errors

```bash
az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "ContainerAppConsoleLogs_CL
    | where ContainerAppName_s == 'continuation'
    | extend log = parse_json(Log_s)
    | where log.status >= 400
    | project TimeGenerated, status=log.status, method=log.method, path=log.path, duration=log.duration, exception=log.exception
    | order by TimeGenerated desc
    | limit 50" \
  -o table
```

### slow

```bash
az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "ContainerAppConsoleLogs_CL
    | where ContainerAppName_s == 'continuation'
    | extend log = parse_json(Log_s)
    | where todouble(log.duration) > 1000
    | project TimeGenerated, duration=log.duration, method=log.method, path=log.path, controller=log.controller, action=log.action
    | order by TimeGenerated desc
    | limit 50" \
  -o table
```

### default (last N lines)

Use the limit from the argument if provided, defaulting to 50:

```bash
az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "ContainerAppConsoleLogs_CL
    | where ContainerAppName_s == 'continuation'
    | extend log = parse_json(Log_s)
    | where isnotempty(log.method)
    | project TimeGenerated, status=log.status, method=log.method, path=log.path, duration=log.duration, controller=log.controller
    | order by TimeGenerated desc
    | limit <N>" \
  -o table
```

Print the results. If the query returns no rows, note that logs may take a few minutes to appear in the workspace after the app first receives traffic, and that non-request logs (startup messages, background errors) won't have a `method` field — omit the `isnotempty(log.method)` filter to see all log lines including plain-text ones.
