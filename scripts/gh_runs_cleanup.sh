#!/usr/bin/env bash
# chmod +x scripts/gh_runs_cleanup.sh

# use egs
# DRY_RUN=true KEEP_PER_WORKFLOW=8 AGE_DAYS=45 REPO=data-to-insight/dfe-csc-api-data-flows bash scripts/gh_runs_cleanup.sh
# DRY_RUN=false KEEP_PER_WORKFLOW=8 bash scripts/gh_runs_cleanup.sh


# Cleanup old GitHub Actions runs, keep latest N per workflow
set -euo pipefail

# Config, can override via env
REPO="${REPO:-}"
WORKFLOWS="${WORKFLOWS:-.github/workflows/release-and-docs.yml}"  # csv
KEEP_PER_WORKFLOW="${KEEP_PER_WORKFLOW:-10}"
AGE_DAYS="${AGE_DAYS:-}"       # optional e.g. 30
LIMIT="${LIMIT:-2000}"         # how many runs to consider
DRY_RUN="${DRY_RUN:-true}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need gh; need jq

# find REPO from git if not given
if [ -z "$REPO" ]; then
  url=$(git config --get remote.origin.url || true)
  if [[ "$url" =~ github.com[:/](.+/.+?)(\.git)?$ ]]; then
    REPO="${BASH_REMATCH[1]}"
  else
    echo "Set REPO=owner/name" >&2; exit 1
  fi
fi

echo "Repo: $REPO"
echo "Workflows: $WORKFLOWS"
echo "Keep per workflow: $KEEP_PER_WORKFLOW"
echo "Age days filter: ${AGE_DAYS:-none}"
echo "Limit: $LIMIT"
echo "DRY_RUN: $DRY_RUN"

# Auth note, prefer non-interactive GITHUB_TOKEN if present
if ! gh auth status -h github.com -t >/dev/null 2>&1; then
  echo "gh not authenticated. If running local, run: gh auth login -s repo -s workflow" >&2
fi

# Fetch runs as JSON
json_runs=$(gh run list -R "$REPO" --limit "$LIMIT" \
  --json databaseId,workflowName,workflowPath,headBranch,createdAt,status,conclusion)

# Build list to delete:
# group by workflowPath, sort desc on createdAt, drop newest KEEP_PER_WORKFLOW,
# then apply AGE_DAYS filter if set
jq_script='
  group_by(.workflowPath)[] |
  sort_by(.createdAt) | reverse |
  .[env.KEEP | tonumber:] |
  .[]
  | {id: .databaseId, path: .workflowPath, createdAt: .createdAt}
'
export KEEP="$KEEP_PER_WORKFLOW"
to_delete=$(jq -c "$jq_script" <<<"$json_runs")

# Optional age filter
if [ -n "${AGE_DAYS}" ]; then
  cutoff=$(date -u -d "-$AGE_DAYS days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
          date -u -v-"$AGE_DAYS"d +%Y-%m-%dT%H:%M:%SZ)
  to_delete=$(jq -c --arg cutoff "$cutoff" 'select(.createdAt < $cutoff)' <<<"$to_delete")
fi

count=$(wc -l <<<"$to_delete" | tr -d ' ')
echo "Will delete $count run(s)"
echo "First ten candidates:"
head -n 10 <<<"$to_delete" | jq -r '.id as $i | "\($i)  \(.path)  \(.createdAt)"'

if [ "$count" -eq 0 ]; then
  echo "Nothing to delete"; exit 0
fi

if [ "$DRY_RUN" != "false" ]; then
  echo "DRY RUN, no deletions performed, set DRY_RUN=false to apply"
  exit 0
fi

# Delete runs
if gh run delete --help 2>/dev/null | grep -q -- '--yes'; then
  confirm="--yes"
  pipe_confirm=false
else
  confirm=""
  pipe_confirm=true
fi

while read -r line; do
  id=$(jq -r '.id' <<<"$line")
  [ -n "$id" ] || continue
  echo "Deleting run $id"
  if $pipe_confirm; then
    printf 'y\n' | gh run delete "$id" -R "$REPO" || echo "WARN, failed on $id" >&2
  else
    gh run delete "$id" -R "$REPO" $confirm || echo "WARN, failed on $id" >&2
  fi
done <<<"$to_delete"

echo "Done"
