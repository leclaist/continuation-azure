Set up secrets for a new Fly.io deployment environment by reading local credentials.

## Usage

Run this skill when creating a new Fly app and you need to populate its secrets from the local environment.

Provide the app name as an argument, e.g. `/add-environment continuation-preview`.

## What to do

1. Read the local `.env` file to get `GOOGLE_DRIVE_FOLDER_ID` and `GOOGLE_SERVICE_ACCOUNT_JSON`.
2. Read `config/master.key` to get `RAILS_MASTER_KEY`.
3. Check if `ANTHROPIC_API_KEY` is set in `.env` (optional — skip silently if absent).
4. Run the following, substituting `APP_NAME` with the argument provided:

```bash
fly secrets set \
  RAILS_MASTER_KEY="$(cat config/master.key)" \
  GOOGLE_DRIVE_FOLDER_ID="<value from .env>" \
  GOOGLE_SERVICE_ACCOUNT_JSON='<value from .env>' \
  --app APP_NAME
```

Add `ANTHROPIC_API_KEY` to the command if it exists in `.env`.

5. Confirm secrets were set by running `fly secrets list --app APP_NAME`.
6. Report which secrets were set and which were skipped (e.g. ANTHROPIC_API_KEY absent).

## Notes

- Never print secret values — only confirm names and digests.
- The `.env` file is gitignored — never commit it or suggest sharing it.
- If `.env` is missing, read `.env.example` to show the user which values they need to fill in, and stop.
