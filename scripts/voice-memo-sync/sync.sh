#!/bin/bash
# Watches macOS Voice Memos and syncs new recordings into the Continuation
# journal's Google Drive folder, converted to mp3 and named after whatever
# custom title the memo has been renamed to in Voice Memos (must match the
# entry-slug convention, e.g. renaming a memo to "Dec-24-2008" syncs it as
# dec-24-2008.mp3). Recordings left with their default (untitled) name are
# not synced -- renaming is the deliberate signal that a memo belongs to a
# specific journal entry.
#
# Apple does not document the Voice Memos database schema, so this script
# discovers the recordings table/columns at runtime instead of hardcoding
# names -- it's more likely to keep working across macOS updates, but if it
# ever can't find what it expects it fails loudly (see ERROR lines) rather
# than silently doing nothing.
set -euo pipefail

DRIVE_FOLDER="$HOME/Library/CloudStorage/GoogleDrive-sleclaire06@gmail.com/My Drive/Continuation/What I Remembered"
WORKDIR="$HOME/.continuation-voice-memo-sync"
STATE_FILE="$WORKDIR/processed_ids.txt"

CANDIDATE_CONTAINERS=(
  "$HOME/Library/Group Containers/group.com.apple.VoiceMemos.shared"
  "$HOME/Library/Group Containers/group.com.apple.VoiceMemos"
  "$HOME/Library/Containers/com.apple.VoiceMemos/Data/Library/Application Support"
)

MODE="run"
case "${1:-}" in
  --dry-run) MODE="dry-run" ;;
  --list)    MODE="list" ;;
esac

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [voice-memo-sync] $*"; }

mkdir -p "$WORKDIR"
if [[ ! -d "$DRIVE_FOLDER" ]]; then
  log "ERROR: Drive folder not found: $DRIVE_FOLDER"
  log "Is Google Drive for desktop running and synced?"
  exit 1
fi

# --- 1. Locate the Voice Memos database ---------------------------------
DB_PATH=""
for base in "${CANDIDATE_CONTAINERS[@]}"; do
  [[ -d "$base" ]] || continue
  found=$(find "$base" -iname "CloudRecordings.db" 2>/dev/null | head -1 || true)
  if [[ -n "$found" ]]; then
    DB_PATH="$found"
    break
  fi
done

if [[ -z "$DB_PATH" ]]; then
  log "ERROR: couldn't find CloudRecordings.db under any known Voice Memos container."
  log "Checked:"
  for base in "${CANDIDATE_CONTAINERS[@]}"; do log "  $base"; done
  log "If these directories exist but are unreadable, grant Full Disk Access to whatever"
  log "is running this script (Terminal.app, or /bin/bash if run via launchd) in"
  log "System Settings > Privacy & Security > Full Disk Access."
  exit 1
fi

log "Using database: $DB_PATH"

# --- 2. Snapshot it (avoids lock contention with the live Voice Memos app) ---
SNAPSHOT="$WORKDIR/CloudRecordings.snapshot.db"
if ! sqlite3 "$DB_PATH" ".backup '$SNAPSHOT'" 2>"$WORKDIR/backup_err.log"; then
  log "ERROR: failed to snapshot database: $(cat "$WORKDIR/backup_err.log")"
  exit 1
fi

# --- 3. Discover the recordings table + path/title columns ----------------
TABLE=$(sqlite3 "$SNAPSHOT" "SELECT name FROM sqlite_master WHERE type='table' AND upper(name) LIKE '%RECORDING%' LIMIT 1;")
if [[ -z "$TABLE" ]]; then
  log "ERROR: no table matching '%RECORDING%' found -- Apple's schema may have changed."
  log "Tables present: $(sqlite3 "$SNAPSHOT" '.tables')"
  exit 1
fi

COLUMNS=$(sqlite3 "$SNAPSHOT" "PRAGMA table_info($TABLE);" | awk -F'|' '{print $2}')
PATH_COL=$(echo "$COLUMNS" | grep -i 'PATH' | head -1)
# Title columns vary by macOS version (seen: ZCUSTOMLABEL, ZENCRYPTEDTITLE --
# the latter is plaintext despite the name). Exclude sort-key variants like
# ZCUSTOMLABELFORSORTING, which hold a normalized copy, not the real value.
TITLE_COLS=$(echo "$COLUMNS" | grep -iE 'LABEL|TITLE' | grep -vi 'SORT')

if [[ -z "$PATH_COL" || -z "$TITLE_COLS" ]]; then
  log "ERROR: couldn't find a path column and a title column in table '$TABLE'."
  log "Columns found: $(echo "$COLUMNS" | tr '\n' ' ')"
  exit 1
fi

coalesce_args=""
while IFS= read -r col; do
  [[ -z "$col" ]] && continue
  coalesce_args+="NULLIF($col,''), "
done <<<"$TITLE_COLS"
TITLE_EXPR="COALESCE(${coalesce_args%, })"

log "Recordings table: $TABLE (path: $PATH_COL, title: $(echo "$TITLE_COLS" | tr '\n' ' '))"

if [[ "$MODE" == "list" ]]; then
  sqlite3 -header -column "$SNAPSHOT" \
    "SELECT Z_PK, $PATH_COL, $TITLE_EXPR AS title FROM $TABLE ORDER BY Z_PK DESC LIMIT 20;"
  exit 0
fi

RECORDINGS_DIR="$(dirname "$DB_PATH")"
[[ -d "$RECORDINGS_DIR/Recordings" ]] && RECORDINGS_DIR="$RECORDINGS_DIR/Recordings"

# --- 4. First run: baseline existing recordings without importing them ---
# Otherwise every voice memo ever recorded would get converted and dropped
# into the journal folder on setup day.
if [[ ! -s "$STATE_FILE" ]]; then
  count=0
  while IFS=$'\t' read -r pk _rest; do
    echo "$pk" >> "$STATE_FILE"
    count=$((count + 1))
  done < <(sqlite3 -separator $'\t' "$SNAPSHOT" "SELECT Z_PK, $PATH_COL FROM $TABLE WHERE $PATH_COL IS NOT NULL;")
  log "First run: baselined $count existing recording(s) as already-seen."
  log "Future runs will only sync recordings made from now on."
  exit 0
fi

# --- 5. Sync new recordings -----------------------------------------------
sqlite3 -separator $'\t' "$SNAPSHOT" \
  "SELECT Z_PK, $PATH_COL, $TITLE_EXPR FROM $TABLE WHERE $PATH_COL IS NOT NULL ORDER BY Z_PK ASC;" |
while IFS=$'\t' read -r pk relpath title; do
  grep -qx "$pk" "$STATE_FILE" && continue

  if [[ -z "$title" ]]; then
    log "SKIP: pk=$pk has no custom title, leaving unprocessed (rename it in Voice Memos to sync it)."
    continue
  fi

  # Trim surrounding whitespace, then lowercase to match the slug convention.
  trimmed="${title#"${title%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  slug=$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')

  if ! [[ "$slug" =~ ^[a-z]{3}-[0-9]{2}-[0-9]{4}$ ]]; then
    log "WARN: pk=$pk title '$title' doesn't look like the mmm-dd-yyyy slug convention -- syncing as '$slug.mp3' anyway, but it likely won't match a journal entry."
  fi

  src="$RECORDINGS_DIR/$relpath"
  if [[ ! -f "$src" ]]; then
    log "WARN: pk=$pk references missing file '$src', skipping."
    continue
  fi

  dest="$DRIVE_FOLDER/$slug.mp3"
  if [[ -f "$dest" ]]; then
    log "SKIP: $dest already exists (another recording for $slug?) -- not overwriting, pk=$pk left unprocessed."
    continue
  fi

  if [[ "$MODE" == "dry-run" ]]; then
    log "[dry-run] would convert '$src' -> '$dest'"
    continue
  fi

  tmp_out="$WORKDIR/$slug.mp3.tmp"
  if ffmpeg -y -loglevel error -i "$src" -ac 1 -b:a 128k -f mp3 "$tmp_out"; then
    mv "$tmp_out" "$dest"
    echo "$pk" >> "$STATE_FILE"
    log "OK: $relpath -> $dest"
  else
    log "ERROR: ffmpeg failed converting '$src', pk=$pk left unprocessed for retry."
    rm -f "$tmp_out"
  fi
done

log "Done."
