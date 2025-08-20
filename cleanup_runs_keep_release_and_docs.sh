#!/usr/bin/env bash
# 
set -euo pipefail


REPO="data-to-insight/dfe-csc-api-data-flows"
KEEP_WORKFLOW_FILE=".github/workflows/release-and-docs.yml"
LIMIT="${LIMIT:-1000}"
DRY_RUN="${DRY_RUN:-true}"

say(){ printf "%s\n" "$*" >&2; }
need(){ command -v "$1" >/dev/null 2>&1 || { say "Missing: $1"; exit 1; }; }
need gh; need awk; need grep; need mktemp

say "== GitHub Actions cleanup (keep only: $KEEP_WORKFLOW_FILE) =="

# --- Temporarily disable Codespaces token so gh can use a user token ---
RESTORE_TOKEN=false
if [ "${GITHUB_TOKEN-}" != "" ]; then
  RESTORE_TOKEN=true
  export __OLD_GITHUB_TOKEN="$GITHUB_TOKEN"
  unset GITHUB_TOKEN
  say "-> Temporarily unsetting GITHUB_TOKEN for interactive gh auth"
fi

# Show current gh status (may be unauthenticated here)
if ! gh auth status -h github.com -t >/dev/null 2>&1; then
  say "-> gh not logged in yet."
fi

say "-> Logging in with scopes: repo, workflow (approve in browser; Authorize SSO if prompted)"
gh auth login -h github.com -p https -s repo -s workflow

say "-> Verifying scopes:"
gh auth status -h github.com -t || true

ALL=$(mktemp); KEEP=$(mktemp); DEL=$(mktemp)
trap 'rm -f "$ALL" "$KEEP" "$DEL"' EXIT

say "-> Fetching ALL run IDs (limit: $LIMIT)"
gh run list -R "$REPO" --limit "$LIMIT" --json databaseId -q '.[].databaseId' > "$ALL"

say "-> Fetching run IDs to KEEP for: $KEEP_WORKFLOW_FILE"
gh run list -R "$REPO" --workflow "$KEEP_WORKFLOW_FILE" --limit "$LIMIT" --json databaseId -q '.[].databaseId' > "$KEEP"

# Compute ALL - KEEP
grep -vxF -f "$KEEP" "$ALL" > "$DEL" || true

COUNT_ALL=$(wc -l < "$ALL" | tr -d ' ')
COUNT_KEEP=$(wc -l < "$KEEP" | tr -d ' ')
COUNT_DEL=$(wc -l < "$DEL" | tr -d ' ')
say "-> Totals: all=$COUNT_ALL, keep=$COUNT_KEEP, delete=$COUNT_DEL"

say "First 10 to delete:"
head "$DEL" | sed 's/^/   /' || true

if [ "$COUNT_DEL" -eq 0 ]; then
  say "Nothing to delete."
else
  if [ "$DRY_RUN" != "false" ]; then
    say "DRY RUN: no deletions performed. Re-run with DRY_RUN=false to apply."
  else
    # Detect if this gh supports --yes on `gh run delete`
    if gh run delete --help 2>/dev/null | grep -q -- '--yes'; then
      CONFIRM_FLAG="--yes"
      PIPE_CONFIRM=false
    else
      CONFIRM_FLAG=""
      PIPE_CONFIRM=true
    fi

    say "-> Deleting $COUNT_DEL runs NOT from $KEEP_WORKFLOW_FILE ..."
    while read -r id; do
      [ -n "$id" ] || continue
      say "   Deleting run $id"
      if $PIPE_CONFIRM; then
        printf 'y\n' | gh run delete "$id" -R "$REPO" || say "   WARN: failed on $id"
      else
        gh run delete "$id" -R "$REPO" $CONFIRM_FLAG || say "   WARN: failed on $id"
      fi
    done < "$DEL"
    say "-> Deletion pass complete."
  fi
fi

say "-> Logging out user token"
gh auth logout -h github.com -y || true

if $RESTORE_TOKEN; then
  export GITHUB_TOKEN="$__OLD_GITHUB_TOKEN"
  unset __OLD_GITHUB_TOKEN
  say "-> Restored Codespaces GITHUB_TOKEN environment"
fi

say "== Done =="