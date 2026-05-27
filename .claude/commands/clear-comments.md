Clear all generated comments from production so they regenerate with the current prompt on next visit.

Run this command, reading the admin token from terraform.tfvars:

```bash
ADMIN_TOKEN=$(grep 'admin_token' infra/terraform.tfvars | sed 's/.*= "\(.*\)"/\1/')
curl -s -X POST https://christineclaymoreau.lol/admin/clear_comments \
  -H "X-Admin-Token: $ADMIN_TOKEN" | cat
```

Report how many comments were deleted based on the JSON response (e.g. `{"deleted":12}`).
