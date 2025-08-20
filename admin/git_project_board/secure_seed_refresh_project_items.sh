#!/usr/bin/env bash
# chmod +x ./git_project_board/secure_seed_refresh_project_items.sh
# ./git_project_board/secure_seed_refresh_project_items.sh

# # Upsert (update by title or create if missing)
# ./git_project_board/secure_seed_refresh_project_items.sh

# # Update-only (no new items created)
# MODE="update" ./git_project_board/secure_seed_refresh_project_items.sh

# # Create-only (skip updates)
# MODE="create" ./git_project_board/secure_seed_refresh_project_items.sh

#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG — edit as needed
OWNER="data-to-insight"
PROJECT_NUMBER="13"

# Roadmap date fields (exact names in your Project)
START_FIELD_NAME="Start date"
END_FIELD_NAME="Target date"

# JSON source (array of items)
JSON_FILE="./git_project_board/project_items.json"

# MODE: upsert | update | create
MODE="upsert"

# Custom fields to write (name => type)
# Supported types: single_select | number | text | date
declare -A FIELD_TYPES=(
  ["Priority"]="single_select"
  ["Size"]="single_select"
  ["Estimate"]="number"
  ["LA"]="text"
  ["Phase"]="number"   # <-- Phase is numeric per your note
)
########################################

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }

# globals for cleanup
TMP_JSON=""

cleanup(){
  echo "Cleaning up GitHub CLI credentials..."
  env -u GITHUB_TOKEN -u GH_TOKEN gh auth logout --hostname github.com --yes >/dev/null 2>&1 || true
  rm -rf "${HOME}/.config/gh" >/dev/null 2>&1 || true
  [[ -n "$TMP_JSON" && -f "$TMP_JSON" ]] && rm -f "$TMP_JSON"
  echo "Cleanup complete."
}
trap cleanup EXIT

echo "→ Checking tools..."
need_cmd gh; need_cmd jq; need_cmd awk

echo "→ Ignore Codespaces token for this session..."
unset GITHUB_TOKEN || true
unset GH_TOKEN || true

echo "→ gh login (scopes: read:project, project, repo, read:org)..."
env -u GITHUB_TOKEN -u GH_TOKEN gh auth login --scopes "read:project,project,repo,read:org"
env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null || { echo "ERROR: gh login failed"; exit 1; }

echo "→ Validate project access..."
env -u GITHUB_TOKEN -u GH_TOKEN gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json >/dev/null 2>&1 \
  || { echo "ERROR: token lacks project scopes or project not accessible"; exit 1; }

# Prepare JSON (strip BOM; ensure array)
echo "→ Validating JSON..."
[[ -f "$JSON_FILE" ]] || { echo "ERROR: missing $JSON_FILE"; exit 1; }
TMP_JSON="$(mktemp)"
awk 'NR==1{sub(/^\xef\xbb\xbf/,"")}1' "$JSON_FILE" > "$TMP_JSON"
jq -e 'type=="array"' "$TMP_JSON" >/dev/null 2>&1 || { echo "ERROR: JSON must be an array"; exit 1; }
JSON_FILE="$TMP_JSON"

echo "→ Fetch project + fields..."
PROJECT_ID=$(env -u GITHUB_TOKEN -u GH_TOKEN gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json | jq -r '.id')
FIELDS_JSON=$(env -u GITHUB_TOKEN -u GH_TOKEN gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json)

# Helpers to resolve field + option IDs
get_field_id(){ # $1 = field name
  local fname="$1"
  echo "$FIELDS_JSON" | jq -r --arg n "$fname" '
    .. | objects | select(has("name") and has("id")) | select(.name==$n) | .id
  ' | head -n1
}
get_single_select_option_id(){ # $1 field name, $2 option name
  local fname="$1" oname="$2"
  echo "$FIELDS_JSON" | jq -r --arg n "$fname" --arg o "$oname" '
    .. | objects
    | select(has("name") and .name==$n and (has("options") or has("configuration")))
    | (.options // .configuration.options // [])
    | .[]? | select(.name==$o) | .id
  ' | head -n1
}
# Extract a TEXT-like field value from an item (tries several shapes)
get_item_text_field_value(){ # $1 = item id, $2 = field name
  local item_id="$1" field_name="$2"
  local j
  j=$(env -u GITHUB_TOKEN -u GH_TOKEN gh project item-view --id "$item_id" --format json) || return 1
  echo "$j" | jq -r --arg n "$field_name" '
    (
      .. | objects
      | select((has("field") and .field.name==$n) or (has("name") and .name==$n))
      | .text // .value // .name // empty
    ) // empty
  ' | head -n1
}

START_FIELD_ID=$(get_field_id "$START_FIELD_NAME")
END_FIELD_ID=$(get_field_id "$END_FIELD_NAME")
[[ -z "$START_FIELD_ID" || -z "$END_FIELD_ID" || "$START_FIELD_ID" == "null" || "$END_FIELD_ID" == "null" ]] && {
  echo "ERROR: Could not find \"$START_FIELD_NAME\" or \"$END_FIELD_NAME\". Check field names in the project."
  echo "$FIELDS_JSON" | jq -r '..|objects|select(has("name") and has("id"))| "\(.name) | \(.id)"'
  exit 1
}

echo "   Found:"
echo "     $START_FIELD_NAME -> $START_FIELD_ID"
echo "     $END_FIELD_NAME   -> $END_FIELD_ID"

echo "→ Index existing items by Title + LA (exact match)..."
LA_FIELD_NAME="LA"
LA_FIELD_ID=$(get_field_id "$LA_FIELD_NAME")

EXISTING=$(env -u GITHUB_TOKEN -u GH_TOKEN gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json)

# Build a map: "Title||LA" -> item_id  (avoid pipelines so loop runs in current shell)
COMPOSITE_TO_ID="{}"
while read -r row; do
  item_id=$(jq -r '.id' <<<"$row")
  item_title=$(jq -r '.title' <<<"$row")
  [[ -z "$item_id" || -z "$item_title" || "$item_id" == "null" || "$item_title" == "null" ]] && continue

  la_value=""
  if [[ -n "$LA_FIELD_ID" && "$LA_FIELD_ID" != "null" ]]; then
    la_value=$(get_item_text_field_value "$item_id" "$LA_FIELD_NAME" || echo "")
  fi

  key="${item_title}||${la_value}"
  COMPOSITE_TO_ID=$(jq -c --arg k "$key" --arg v "$item_id" '. + {($k): $v}' <<<"$COMPOSITE_TO_ID")
done < <(echo "$EXISTING" | jq -c '.. | objects | select(has("id") and has("title")) | {id, title}')

items_total=$(jq 'length' "$JSON_FILE")
echo "→ Processing $items_total rows ($MODE)..."

idx=0
# Again, use process substitution to keep loop in current shell
while read -r row; do
  idx=$((idx+1))
  TITLE=$(echo "$row"  | jq -r '.title')
  BODY=$(echo "$row"   | jq -r '.body // empty')
  START=$(echo "$row"  | jq -r '.start // empty')
  END=$(echo "$row"    | jq -r '.end // empty')
  LA_VAL=$(echo "$row" | jq -r '.LA // .la // empty')

  if [[ -z "$TITLE" || "$TITLE" == "null" ]]; then
    echo "[$idx/$items_total] Skipping item with no title."
    continue
  fi

  COMP_KEY="${TITLE}||${LA_VAL}"
  ITEM_ID=$(echo "$COMPOSITE_TO_ID" | jq -r --arg k "$COMP_KEY" '.[$k] // empty')

  if [[ -n "$ITEM_ID" && "$MODE" != "create" ]]; then
    echo "[$idx/$items_total] Update: $TITLE (LA=${LA_VAL})"
  elif [[ -z "$ITEM_ID" && "$MODE" != "update" ]]; then
    echo "[$idx/$items_total] Create: $TITLE (LA=${LA_VAL})"
    ITEM_JSON=$(env -u GITHUB_TOKEN -u GH_TOKEN gh project item-create "$PROJECT_NUMBER" --owner "$OWNER" \
                --title "$TITLE" ${BODY:+--body "$BODY"} --format json)
    ITEM_ID=$(echo "$ITEM_JSON" | jq -r '.id')
    COMPOSITE_TO_ID=$(jq -c --arg k "$COMP_KEY" --arg v "$ITEM_ID" '. + {($k): $v}' <<<"$COMPOSITE_TO_ID")
  else
    echo "[$idx/$items_total] Skip (mode=$MODE): $TITLE (LA=${LA_VAL})"
    continue
  fi

  # Dates
  if [[ -n "$START" && "$START" != "null" ]]; then
    env -u GITHUB_TOKEN -u GH_TOKEN gh project item-edit \
      --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$START_FIELD_ID" \
      --date "$START" >/dev/null
  fi
  if [[ -n "$END" && "$END" != "null" ]]; then
    env -u GITHUB_TOKEN -u GH_TOKEN gh project item-edit \
      --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$END_FIELD_ID" \
      --date "$END" >/dev/null
  fi

  # Extra fields
  for FNAME in "${!FIELD_TYPES[@]}"; do
    # Accept both exact-case and lower_snake in JSON (e.g., "Priority" or "priority")
    VAL=$(echo "$row" | jq -r --arg k1 "$FNAME" --arg k2 "$(echo "$FNAME" | tr '[:upper:] ' '[:lower:]_')" '.[$k1] // .[$k2] // empty')
    [[ -z "$VAL" || "$VAL" == "null" ]] && continue

    FIELD_ID=$(get_field_id "$FNAME")
    if [[ -z "$FIELD_ID" || "$FIELD_ID" == "null" ]]; then
      echo "      (!) Project field \"$FNAME\" not found; skipping."
      continue
    fi

    TYPE="${FIELD_TYPES[$FNAME]}"
    case "$TYPE" in
      single_select)
        OPT_ID=$(get_single_select_option_id "$FNAME" "$VAL")
        if [[ -z "$OPT_ID" || "$OPT_ID" == "null" ]]; then
          echo "      (!) Option \"$VAL\" not found for \"$FNAME\"; skipping."
          continue
        fi
        env -u GITHUB_TOKEN -u GH_TOKEN gh project item-edit \
          --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" \
          --single-select-option-id "$OPT_ID" >/dev/null
        ;;
      number)
        # ensure numeric; if not, write as text
        if [[ "$VAL" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
          if ! env -u GITHUB_TOKEN -u GH_TOKEN gh project item-edit \
                 --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" \
                 --number "$VAL" >/dev/null 2>&1; then
            echo "      (!) Number update failed for \"$FNAME\"; writing as text."
            env -u GITHUB_TOKEN -u GH_TOKEN gh project item-edit \
              --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" \
              --text "$VAL" >/dev/null
          fi
        else
          echo "      (!) \"$FNAME\" value \"$VAL\" is not numeric; writing as text."
          env -u GITHUB_TOKEN -u GH_TOKEN gh project item-edit \
            --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" \
            --text "$VAL" >/dev/null
        fi
        ;;
      date)
        env -u GITHUB_TOKEN -u GH_TOKEN gh project item-edit \
          --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" \
          --date "$VAL" >/dev/null
        ;;
      text|*)
        env -u GITHUB_TOKEN -u GH_TOKEN gh project item-edit \
          --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" \
          --text "$VAL" >/dev/null
        ;;
    esac
  done
done < <(jq -c '.[]' "$JSON_FILE")

echo "Done ($MODE). In Roadmap, map: Start = \"$START_FIELD_NAME\", End = \"$END_FIELD_NAME\"."
echo "   Credentials will be purged automatically now."
