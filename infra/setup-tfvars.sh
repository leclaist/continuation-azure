#!/usr/bin/env bash
# Generates infra/terraform.tfvars from local credentials.
# Run from the repo root: ./infra/setup-tfvars.sh <service-account.json>
#
# The service account JSON must be a file path. The Rails master key is read
# from config/master.key. You will be prompted for anything else not set.
#
# Optional env vars:
#   GOOGLE_DRIVE_FOLDER_ID   — skip the prompt
#   ANTHROPIC_API_KEY        — skip the prompt (press enter to omit)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/infra/terraform.tfvars"

# --- service account JSON ------------------------------------------------
SA_JSON_PATH="${1:-}"
if [[ -z "$SA_JSON_PATH" ]]; then
  echo "Usage: $0 <path-to-service-account.json>" >&2
  exit 1
fi
if [[ ! -f "$SA_JSON_PATH" ]]; then
  echo "Error: file not found: $SA_JSON_PATH" >&2
  exit 1
fi

# --- rails master key ----------------------------------------------------
MASTER_KEY_FILE="$REPO_ROOT/config/master.key"
if [[ ! -f "$MASTER_KEY_FILE" ]]; then
  echo "Error: config/master.key not found — are you in the right repo?" >&2
  exit 1
fi
RAILS_MASTER_KEY=$(cat "$MASTER_KEY_FILE")

# --- google drive folder id ----------------------------------------------
if [[ -z "${GOOGLE_DRIVE_FOLDER_ID:-}" ]]; then
  read -rp "Google Drive folder ID: " GOOGLE_DRIVE_FOLDER_ID
fi

# --- anthropic api key ---------------------------------------------------
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  read -rp "Anthropic API key (press enter to omit): " ANTHROPIC_API_KEY
fi

# --- write tfvars (Python handles the HCL escaping) ----------------------
export ANTHROPIC_API_KEY
python3 - <<PYEOF
import json, os

with open("$SA_JSON_PATH") as f:
    sa = json.load(f)

# Compact JSON, then double-escape backslashes for Terraform HCL double-quoted
# strings. Terraform interprets \\\\ as \\ and \\" as ", so \\\\n in the file
# becomes \\n in the value, which JSON.parse then reads as a newline.
sa_single = json.dumps(sa)
sa_hcl = sa_single.replace('\\\\', '\\\\\\\\').replace('"', '\\\\"')

anthropic = os.environ.get("ANTHROPIC_API_KEY", "")

lines = [
    'rails_master_key            = "$RAILS_MASTER_KEY"',
    'google_drive_folder_id      = "$GOOGLE_DRIVE_FOLDER_ID"',
    f'google_service_account_json = "{sa_hcl}"',
]
if anthropic:
    lines.append(f'anthropic_api_key           = "{anthropic}"')

with open("$OUT", "w") as f:
    f.write("\\n".join(lines) + "\\n")

print(f"Wrote $OUT")
PYEOF
