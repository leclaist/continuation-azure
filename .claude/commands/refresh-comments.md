Wipe all generated comments and the commenter roster/memory, then regenerate every entry's comments oldest-to-newest, so the recurring commenters' continuity is rebuilt cleanly from scratch. Use this after changing `CommentGeneratorService`'s prompt or the commenter memory logic — a plain `/clear-comments` leaves stale commenter memory in place.

This is slower than `/clear-comments`: it makes one Claude API call per journal entry, sequentially, in date order (memory for each entry depends on the ones before it). Run it against staging first and spot-check a couple of entries in the browser for continuity before running it against production.

`ADMIN_TOKEN` is the same value across all three deployed environments. Read it from `terraform.tfvars`:

```bash
ADMIN_TOKEN=$(grep 'admin_token' infra/terraform.tfvars | sed 's/.*= "\(.*\)"/\1/')

curl -s -X POST https://continuation-staging.fly.dev/admin/refresh_comments \
  -H "X-Admin-Token: $ADMIN_TOKEN" | cat
```

After confirming staging looks right, run it against production:

```bash
curl -s -X POST https://christineclaymoreau.lol/admin/refresh_comments \
  -H "X-Admin-Token: $ADMIN_TOKEN" | cat
curl -s -X POST https://continuation.fly.dev/admin/refresh_comments \
  -H "X-Admin-Token: $ADMIN_TOKEN" | cat
```

Report `entries_processed` and `commenters` from each JSON response (e.g. `{"entries_processed":11,"commenters":5}`).
