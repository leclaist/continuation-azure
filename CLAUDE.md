# Continuation

Personal journal reader for Christine Clay Moreau. Content lives in Google Drive — the app reads and renders it. No CMS, no admin interface.

## Key facts

- **Content source**: Google Drive folder (read-only, service account). Files are named by date. No content in the database.
- **Database**: SQLite — stores only visitor counter and cached AI-generated comments.
- **Deployment**: Fly.io (`ord` region). Pushes to `main` auto-deploy via GitHub Actions.
- **Ruby**: `.ruby-version` is `4.0.5` (production). Local may differ — don't be surprised by rbenv errors when running generators.

## Commands

```bash
bin/dev                  # local dev server
bin/rails test           # test suite
bin/brakeman --no-pager  # static security analysis
bin/bundler-audit        # CVE check
git push                 # triggers CI + auto-deploy to Fly
```

```bash
fly ssh console --command "/rails/bin/rails runner '...'"  # run code on prod
fly logs                                                    # tail prod logs
```

## Architecture

**Routes**: `/` → home (year list), `/:year` → entry list, `/:year/:slug` → entry

**GoogleDriveService** (`app/services/google_drive_service.rb`): all Drive access. Results cached 1hr (file list) and per-file (entry HTML). Cache key is `drive/file/:id`.

**CommentGeneratorService** (`app/services/comment_generator_service.rb`): generates era-appropriate fake blog comments + reply threads via Claude Haiku. Comments are stored in `generated_comments` table with a SHA-256 hash of the entry HTML. Stale hash → regenerate. Requires `ANTHROPIC_API_KEY`.

**Year theming**: `data-year` attribute on `<body>` drives CSS. 2008 = MySpace/emo, 2009 = cosmic/neon. Defined in `app/assets/stylesheets/application.css` and `app/helpers/year_theme_helper.rb`.

**Banner ads**: configured per-year in `config/banner_ads.yml`, rendered via `app/views/shared/_banner_ad.html.erb`.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `GOOGLE_DRIVE_FOLDER_ID` | Yes | Drive folder containing journal files |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Yes | Service account JSON (single-line string) |
| `ANTHROPIC_API_KEY` | No | Enables AI comment generation |

## CI / automation

- **CI** runs on every PR and push: Brakeman, bundler-audit, importmap audit, RuboCop, tests
- **Dependabot PRs** auto-merge when CI passes
- **Weekly Monday 9am UTC**: `Update Ruby and dependencies` workflow updates Ruby + gems, opens and merges a PR automatically

## Skills

| Skill | What it does |
|---|---|
| `/update-deps` | Audit, update Ruby + gems locally, commit and push |
| `/clear-comments` | Delete all cached comments from production so they regenerate on next visit |
