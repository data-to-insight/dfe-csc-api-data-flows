#!/bin/bash
# chmod +x remove_file_history.sh
# ./remove_file_history.sh

## needs
# sudo apt update
# sudo apt install git-filter-repo

# USe ONLY to clear out commits from single files when non-public data fails git sec checks etc

# CONFIG
REPO_URL="https://github.com/data-to-insight/dfe-csc-api-data-flows.git"
FILE_TO_REMOVE="api_pipeline_pshell/phase_1_api_payload.ps1"
WORK_DIR="repo_clean_mirror"
FILTER_REPO_CMD="git filter-repo"  # Adjust if needed

# Chk git-filter-repo is installed (as Git subcommand)
if ! git filter-repo --help &> /dev/null; then
  echo "git-filter-repo not installed or not in PATH."
  echo "Try: sudo apt install git-filter-repo OR pipx install git-filter-repo"
  exit 1
fi

# Clone mirror
echo "Cloning mirror of the repo..."
rm -rf "$WORK_DIR"
git clone --mirror "$REPO_URL" "$WORK_DIR"
cd "$WORK_DIR" || exit 1

# Run filter
echo "Remove all history of : $FILE_TO_REMOVE"
$FILTER_REPO_CMD --path "$FILE_TO_REMOVE" --invert-paths

# Force push cleaned history
echo "Force pushing rewritten history to: $REPO_URL"
git remote set-url origin "$REPO_URL"
git push --force --mirror

echo "File '$FILE_TO_REMOVE' removed from history and pushed to Git"
