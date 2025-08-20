#!/usr/bin/env bash
# chmod +x ./rebaseline_repo.sh

# # Rollback/restore ref
# cd ../dfe-csc-api-data-flows.pre-rebaseline.backup.git
# git push --force --prune --tags origin --all

set -euo pipefail

# Usage: ./rebaseline_repo.sh [default_branch]
# Default branch assumed to be 'main' if not provided.
DEFAULT_BRANCH="${1:-main}"

echo "== Rebaseline to a single commit on branch '$DEFAULT_BRANCH' =="

# 0) Preconditions
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repo."
  exit 1
fi

# Ensure working tree is clean-ish; commit current state
echo "-> Staging all current changes to capture present state"
git add -A
if ! git diff --cached --quiet; then
  MSG="Rebaseline: single-commit history as of $(date -u +%F) (UTC)"
  GIT_COMMITTER_DATE="$(date -u)" GIT_AUTHOR_DATE="$(date -u)" git commit -m "$MSG"
else
  echo "No unstaged changes; proceeding with current HEAD tree."
fi

# Safety backup (mirror clone) 
REPO_URL="$(git remote get-url origin)"
REPO_DIR_NAME="$(basename -s .git "$(git rev-parse --show-toplevel)")"
BACKUP_DIR="../${REPO_DIR_NAME}.pre-rebaseline.backup.git"

echo "-> Creating mirror backup at: $BACKUP_DIR"
git clone --mirror "$REPO_URL" "$BACKUP_DIR" >/dev/null

# Create orphan branch with only curr tree
TMP_BRANCH="__rebaseline_tmp__"
echo "-> Creating orphan branch '$TMP_BRANCH'"
git checkout --orphan "$TMP_BRANCH" >/dev/null

# Reset index to nothing and re-add current tree
git rm -r --cached . >/dev/null 2>&1 || true
git add -A
MSG="Rebaseline: initial-commit history as of $(date -u +%F) (UTC)"
GIT_COMMITTER_DATE="$(date -u)" GIT_AUTHOR_DATE="$(date -u)" git commit -m "$MSG" >/dev/null

# Replace default branch with orphan branch
echo "-> Replacing '$DEFAULT_BRANCH' with '$TMP_BRANCH'"
git branch -M "$TMP_BRANCH" "$DEFAULT_BRANCH"

# Clean up local tags -align to remote later
EXISTING_TAGS=$(git tag -l || true)
if [ -n "$EXISTING_TAGS" ]; then
  echo "-> Deleting local tags"
  git tag -d $EXISTING_TAGS >/dev/null
fi

# Push new single-commit history
echo "-> Force-pushing new '$DEFAULT_BRANCH' (disable branch protection first if it fails)"
git push origin "+$DEFAULT_BRANCH:$DEFAULT_BRANCH"

# Delete ALL other remote branches
echo "-> Deleting remote branches (except '$DEFAULT_BRANCH')"
git fetch origin --prune >/dev/null
for BR in $(git ls-remote --heads origin | awk '{print $2}' | sed 's#refs/heads/##'); do
  if [ "$BR" != "$DEFAULT_BRANCH" ]; then
    echo "   - deleting remote branch: $BR"
    git push origin --delete "$BR" >/dev/null || true
  fi
done

# Delete ALL remote tags
echo "-> Deleting remote tags"
REMOTE_TAGS=$(git ls-remote --tags --quiet origin | awk '{print $2}' | sed 's#refs/tags/##' | sed 's#\^\{\}##' | sort -u)
if [ -n "$REMOTE_TAGS" ]; then
  for TAG in $REMOTE_TAGS; do
    echo "   - deleting tag: $TAG"
    git push origin ":refs/tags/$TAG" >/dev/null || true
  done
fi

# tidy & verification
echo "-> Pruning and GC"
git remote prune origin >/dev/null
git reflog expire --expire=now --all
git gc --prune=now --aggressive >/dev/null

echo "-> Verifying no history beyond initial commit..."
COMMITS=$(git rev-list --count "$DEFAULT_BRANCH")
echo "   Commits on '$DEFAULT_BRANCH': $COMMITS"
if [ "$COMMITS" -ne 1 ]; then
  echo "Warning: expected exactly 1 commit on '$DEFAULT_BRANCH'."
fi

echo "== Done. Repo rebaselined to commit on '$DEFAULT_BRANCH'. =="
