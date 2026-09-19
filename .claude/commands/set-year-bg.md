Set or replace the background image for a given year's theme.

## Usage

`/set-year-bg <year> <image-source>`

- `<year>` — four-digit year, e.g. `2008` or `2009`
- `<image-source>` — either a URL to download from, or a local file path (absolute or `~/…`)

## What to do

### 1. Get the image

**If a URL:** download it with curl.
**If a local path:** copy it. Use `find` + `xargs` if the path contains spaces (plain `cp` can fail):
```bash
find <directory> -name "<filename>" -print0 | xargs -0 -I{} cp {} <destination>
```

Save to `app/assets/images/bg-<year>.<ext>` where `<ext>` is jpg, png, etc.

Show the image to the user before continuing.

If the file is over 2MB, resize it to a max of 1920px on the longest side using `sips`:
```bash
sips -Z 1920 app/assets/images/bg-<year>.<ext>
```

### 2. Update the CSS

Open `app/assets/stylesheets/application.css` and find the `[data-year="<year>"]` block.

Make sure it has these background properties (add or update — do not duplicate):
```css
[data-year="<year>"] {
  background-size: cover;
  background-position: center;
  background-attachment: fixed;
}
```

Remove any `background-image` that was previously set in CSS (the URL is injected via ERB instead).

### 3. Update the layout

Open `app/views/layouts/application.html.erb`.

Look for an existing `<% if content_for(:theme_year) == "<year>" %>` block. If one exists, update its `asset_path` call to the new filename. If none exists, add one after the existing theme-year style blocks:

```erb
<% if content_for(:theme_year) == "<year>" %>
  <style>[data-year="<year>"] { background-image: url('<%= asset_path("bg-<year>.<ext>") %>'); }</style>
<% end %>
```

### 4. Remove the old image (if replacing)

If a previous `bg-<year>.*` file exists with a different extension, delete it:
```bash
git rm app/assets/images/bg-<year>.<old-ext>
```

### 5. Verify

Run `docker compose exec web bin/rails test` (`docker compose run --rm web bin/rails test` if the app isn't already up). This step edits `application.html.erb`, which renders on every page — a broken edit here isn't cosmetic, it takes the whole site down (see CLAUDE.md's CI / automation section for what a broken layout edit did once). If anything fails, fix it before continuing — do not commit or push with a failing suite.

### 6. Commit and push

```bash
git add app/assets/images/bg-<year>.<ext> app/assets/stylesheets/application.css app/views/layouts/application.html.erb
git commit -m "Update <year> background image"
git push
```
