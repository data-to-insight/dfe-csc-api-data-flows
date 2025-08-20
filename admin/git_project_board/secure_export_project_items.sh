#!/usr/bin/env bash

# chmod +x ./git_project_board/secure_export_project_items.sh
# ./git_project_board/secure_export_project_items.sh

set -euo pipefail

OWNER="data-to-insight"
PROJECT_NUMBER=13

START_FIELD_NAME="Start date"
END_FIELD_NAME="Target date"
EXPORT_FILE="./git_project_board/project_export.json"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need gh; need jq

unset GITHUB_TOKEN GH_TOKEN || true

echo "→ gh login (scopes: read:project,project,repo,read:org)..."
gh auth login --scopes "read:project,project,repo,read:org" >/dev/null || true
gh auth status >/dev/null

echo "→ Resolving project (owner=$OWNER, number=$PROJECT_NUMBER)..."
PROJECT_ID=$(
  gh api graphql -f query='
    query($owner:String!, $number:Int!){
      organization(login:$owner){
        projectV2(number:$number){ id }
      }
    }' -F owner="$OWNER" -F number="$PROJECT_NUMBER" --jq '.data.organization.projectV2.id'
) || { echo "ERROR: GraphQL call failed while resolving project id"; exit 1; }

if [[ -z "${PROJECT_ID:-}" || "${PROJECT_ID:-null}" == "null" ]]; then
  echo "ERROR: Could not resolve project id. Check owner/number & access."
  exit 1
fi
echo "   Project ID: $PROJECT_ID"

# GraphQL with union fragments + pagination
read -r -d '' GQL <<'GRAPHQL'
query($projectId:ID!, $after:String) {
  node(id:$projectId) {
    ... on ProjectV2 {
      items(first:100, after:$after) {
        nodes {
          id
          content {
            __typename
            ... on Issue { title body }
            ... on PullRequest { title body }
            ... on DraftIssue { title body }
          }
          fieldValues(first:50) {
            nodes {
              __typename
              ... on ProjectV2ItemFieldDateValue {
                date
                field { ... on ProjectV2FieldCommon { name } }
              }
              ... on ProjectV2ItemFieldTextValue {
                text
                field { ... on ProjectV2FieldCommon { name } }
              }
              ... on ProjectV2ItemFieldNumberValue {
                number
                field { ... on ProjectV2FieldCommon { name } }
              }
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2FieldCommon { name } }
              }
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
GRAPHQL

echo "→ Fetching items + field values (with pagination)…"
ALL_NODES="[]"
AFTER=""
PAGE=0
while :; do
  PAGE=$((PAGE+1))
  echo "   • Page $PAGE ..."
  PAGE_JSON=$(gh api graphql -f query="$GQL" -F projectId="$PROJECT_ID" ${AFTER:+-F after="$AFTER"} ) \
    || { echo "ERROR: GraphQL page fetch failed (page $PAGE)"; exit 1; }

  PAGE_NODES=$(echo "$PAGE_JSON" | jq '.data.node.items.nodes')
  # Merge arrays safely
  ALL_NODES=$(jq -c --argjson a "$ALL_NODES" --argjson b "$PAGE_NODES" '$a + $b' <<< '{}' | jq -c '.a + .b' \
    --argjson a "$ALL_NODES" --argjson b "$PAGE_NODES") || { echo "ERROR: jq merge failed"; exit 1; }

  HAS_NEXT=$(echo "$PAGE_JSON" | jq -r '.data.node.items.pageInfo.hasNextPage')
  if [[ "$HAS_NEXT" != "true" ]]; then break; fi
  AFTER=$(echo "$PAGE_JSON" | jq -r '.data.node.items.pageInfo.endCursor')
done

TMP_OUT="$(mktemp)"
echo "→ Transforming to $TMP_OUT ..."
START_FIELD_NAME="$START_FIELD_NAME" END_FIELD_NAME="$END_FIELD_NAME" jq '
  map({
    title: (.content.title // empty),
    body:  (.content.body  // empty),
    start: ((.fieldValues.nodes[]? | select(.field.name == env.START_FIELD_NAME) | .date) // empty),
    end:   ((.fieldValues.nodes[]? | select(.field.name == env.END_FIELD_NAME)   | .date) // empty),
    Priority: ((.fieldValues.nodes[]? | select(.field.name == "Priority") | .name) // (.fieldValues.nodes[]? | select(.field.name == "Priority") | .text) // empty),
    Size:     ((.fieldValues.nodes[]? | select(.field.name == "Size")     | .name) // (.fieldValues.nodes[]? | select(.field.name == "Size")     | .text) // empty),
    Estimate: ((.fieldValues.nodes[]? | select(.field.name == "Estimate") | .number) // (.fieldValues.nodes[]? | select(.field.name == "Estimate") | .text) // empty),
    LA:       ((.fieldValues.nodes[]? | select(.field.name == "LA")       | .text) // (.fieldValues.nodes[]? | select(.field.name == "LA")       | .name) // empty),
    Phase:    ((.fieldValues.nodes[]? | select(.field.name == "Phase")    | .number) // (.fieldValues.nodes[]? | select(.field.name == "Phase")    | .text) // empty)
  } | with_entries(select(.value != null and .value != "")))
' <<<"$ALL_NODES" > "$TMP_OUT" || { echo "ERROR: jq transform failed"; exit 1; }

COUNT=$(jq 'length' "$TMP_OUT")
mv "$TMP_OUT" "$EXPORT_FILE"
echo "Exported $COUNT items → $EXPORT_FILE"

# Optional: log out & wipe stored creds
gh auth logout --hostname github.com --yes >/dev/null 2>&1 || true
rm -rf "${HOME}/.config/gh" >/dev/null 2>&1 || true
