Show recent Azure production logs for the continuation app.

## Usage

`/view-logs` — show the last 50 log lines
`/view-logs <n>` — show the last n lines
`/view-logs follow` — tail live logs (streams until interrupted)

## What to do

If the argument is `follow`, run the live tail command:

```bash
az containerapp logs show \
  --name continuation \
  --resource-group continuation-rg \
  --follow
```

Otherwise, run a Log Analytics query. Use the limit from the argument if provided, defaulting to 50:

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group continuation-rg \
  --workspace-name continuation-logs \
  --query customerId -o tsv)

az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'continuation' | project TimeGenerated, Log_s | order by TimeGenerated desc | limit <N>" \
  -o table
```

Print the results. If the query returns no rows, note that logs may take a few minutes to appear in the workspace after the app first receives traffic.
