Update Ruby version, Rails, and all gem dependencies for this Rails app. Follow these steps exactly, in order, without asking clarifying questions.

## 1. Audit current dependencies
Run `bin/bundler-audit` and capture the output. If vulnerabilities are found, show them to the user and stop — do not proceed with updates.

## 2. Check Ruby version
- Read `.ruby-version` for the current version
- Run: `curl -fsSL "https://endoflife.date/api/ruby.json" | jq -r --arg today "$(date +%Y-%m-%d)" '[.[] | select(.eol == false or .eol > $today)] | sort_by(.latest | split(".") | map(tonumber)) | last | .latest'`
- If the latest differs from current, update `.ruby-version` with the new version

## 3. Update gems
Run:
```
bundle config set --local frozen false
bundle update --all
```

## 4. Audit updated dependencies
Run `bin/bundler-audit` again. If vulnerabilities remain after updating, show them and stop — do not commit.

## 5. Report and commit
- Run `git diff --stat` to show what changed
- Commit with: `git add .ruby-version Gemfile.lock && git commit -m "chore: update Ruby and gem dependencies"`
- Push with: `git push`

Keep the summary short: Ruby old → new, Rails version after update, number of gems changed.
