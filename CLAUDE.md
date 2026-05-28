# Continuation

Personal journal reader for Christine Clay Moreau. Content lives in Google Drive — the app reads and renders it. No CMS, no admin interface.

## Key facts

- **Content source**: Google Drive folder (read-only, service account). Files are named by date. No content in the database.
- **Database**: SQLite — stores only visitor counter and cached AI-generated comments.
- **Deployment**: Fly.io (`ord` region). Two environments — staging and production. Pushes to `main` deploy staging first, smoke test it, then deploy production.
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
# Staging: https://continuation-staging.fly.dev
fly ssh console --app continuation-staging --command "/rails/bin/rails runner '...'"
fly logs --app continuation-staging

# Production: https://continuation.fly.dev
fly ssh console --command "/rails/bin/rails runner '...'"
fly logs
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
- **Deploy pipeline** (push to `main`): staging deploy → smoke test `continuation-staging.fly.dev` → production deploy. Production never deploys if staging smoke test fails.
- **Dependabot PRs** auto-merge when CI passes
- **Weekly Monday 9am UTC**: `Update Ruby and dependencies` workflow updates Ruby + gems, opens and merges a PR automatically

### GitHub Actions secrets

| Secret | Used by |
|---|---|
| `FLY_API_TOKEN` | Production deploy |
| `FLY_STAGING_API_TOKEN` | Staging deploy (scoped to `continuation-staging`) |

## Testing

`bin/rails test` runs the full suite. Tests live in `test/` mirroring `app/` structure.

**When to add or update tests:**
- New controller action → add a test in `test/controllers/`
- New model method or validation → add a test in `test/models/`
- New helper method with logic → add a test in `test/helpers/`
- Changed behaviour → update the corresponding test

**Patterns in use:**
- Controllers: stub `GoogleDriveService.new` (and `CommentGeneratorService.new` for entries) using the `stub` helper in `test_helper.rb`. Use `fake_entry` and `fake_drive_service` to build doubles.
- Models: plain `ActiveSupport::TestCase` — transactional fixtures handle teardown automatically.
- Helpers: include the module directly in an `ActiveSupport::TestCase` subclass.
- `with_env` in `EntriesControllerTest` is the pattern for temporarily setting ENV vars in a test.

**What's intentionally not tested:**
- `GoogleDriveService` (pure API adapter)
- `CommentGeneratorService#generate` (calls Anthropic API — use caching layer tests instead)

## Skills

| Skill | What it does |
|---|---|
| `/update-deps` | Audit, update Ruby + gems locally, commit and push |
| `/clear-comments` | Delete all cached comments from production so they regenerate on next visit |
