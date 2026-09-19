Update Ruby version, Rails, and all gem dependencies for this Rails app. Follow these steps exactly, in order, without asking clarifying questions.

## 1. Audit current dependencies
Run `bin/bundler-audit` and capture the output. If vulnerabilities are found, show them to the user and stop — do not proceed with updates.

## 2. Check Ruby version
- Read `.ruby-version` for the current version
- Run: `curl -fsSL "https://endoflife.date/api/ruby.json" | jq -r --arg today "$(date +%Y-%m-%d)" '[.[] | select(.eol == false or .eol > $today)] | sort_by(.latest | split(".") | map(tonumber)) | last | .latest'`
- If the latest differs from current, update `.ruby-version` with the new version
- Also update the `ARG RUBY_VERSION=` line in `Dockerfile` **and** `Dockerfile.dev` to match — both images must run the same Ruby as the app (mismatched gem native-extension ABIs won't necessarily error, they'll just silently run on a stale interpreter)

## 3. Update gems
- Snapshot the current lockfile first: `cp Gemfile.lock /tmp/Gemfile.lock.before`
- Run:
```
bundle config set --local frozen false
bundle update --all
```

## 4. Check for major version bumps
Compare each gem's version between `/tmp/Gemfile.lock.before` and the new `Gemfile.lock`:
```ruby
def versions(path)
  File.read(path).scan(/^ {4}(\S+) \(([\d]+(?:\.[\d]+)*)/).each_with_object({}) { |(n, v), h| h[n] = v }
end
before = versions("/tmp/Gemfile.lock.before")
after  = versions("Gemfile.lock")
bumps = after.filter_map do |gem, new_v|
  old_v = before[gem]
  next unless old_v
  next if old_v.split(".").first == new_v.split(".").first
  "#{gem}: #{old_v} -> #{new_v}"
end
```
This is exactly the class of bug that broke production once before — a `json` 2.x → 3.0 bump changed `JSON.parse`'s signature and broke every request carrying an existing session cookie (see CLAUDE.md's CI / automation section for the full incident). Handle any bump found the same way the automated weekly workflow does (`.github/workflows/update-dependencies.yml`), without asking:
- If the gem is **not** already an explicit dependency in `Gemfile`: add `gem "<name>", "< <next major>"` to the Gemfile, then rerun `bundle update --all`. If that now resolves without any remaining major bumps, continue normally and note the pin in the final summary.
- If the gem **is** already an explicit `Gemfile` dependency, or the pin doesn't resolve the bump: stop here, show the user exactly which gem(s) bumped and why remediation wasn't attempted/didn't work, and do not commit or push. This needs a human decision, same as an unresolved vulnerability in the steps above.

## 5. Audit updated dependencies
Run `bin/bundler-audit` again. If vulnerabilities remain after updating, show them and stop — do not commit.

## 6. Run the test suite
Run `docker compose exec web bin/rails test` (`docker compose run --rm web bin/rails test` if the app isn't already up). If anything fails, show the failure and stop — do not commit. This is what actually exercises the encrypted-session-cookie code path (`test/integration/session_persistence_test.rb`) that a major gem bump can silently break, so don't skip it even though it wasn't part of this skill before.

## 7. Report and commit
- Run `git diff --stat` to show what changed
- Commit with: `git add .ruby-version Dockerfile Dockerfile.dev Gemfile Gemfile.lock && git commit -m "chore: update Ruby and gem dependencies"`
- Push with: `git push`

Keep the summary short: Ruby old → new, Rails version after update, number of gems changed, and any major version bump encountered and how it was handled.
