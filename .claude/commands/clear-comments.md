Clear all generated comments so they regenerate with the current prompt on next visit. This deletes `generated_comments` only — the `Commenter` roster and memory are left intact, so regenerated comments keep continuity with what's already there. (Use `/refresh-comments` instead if you want commenter memory rebuilt from scratch too.)

`ADMIN_TOKEN` is the same value across all three deployed environments. Read it from `terraform.tfvars` and hit each environment's `/admin/clear_comments`:

```bash
ADMIN_TOKEN=$(grep 'admin_token' infra/terraform.tfvars | sed 's/.*= "\(.*\)"/\1/')

curl -s -X POST https://christineclaymoreau.lol/admin/clear_comments \
  -H "X-Admin-Token: $ADMIN_TOKEN" | cat
curl -s -X POST https://continuation-staging.fly.dev/admin/clear_comments \
  -H "X-Admin-Token: $ADMIN_TOKEN" | cat
curl -s -X POST https://continuation.fly.dev/admin/clear_comments \
  -H "X-Admin-Token: $ADMIN_TOKEN" | cat
```

Report how many comments were deleted per environment based on each JSON response (e.g. `{"deleted":12}`).
