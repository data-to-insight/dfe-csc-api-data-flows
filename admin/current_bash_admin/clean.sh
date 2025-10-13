#!/bin/bash
# chmod +x scripts/clean.sh

# Local dev cleanup, safe by default, DRY_RUN on
# development environment cleanup script, remove common build artifacts, compiled files, and dev clutter
# keeps release_bundle, docs, and site by default, uses DRY_RUN, + only removes IDE folders if explicitly asked! 

set -euo pipefail

DRY_RUN="${DRY_RUN:-true}"        # set DRY_RUN=false to actually delete
FULL="${FULL:-false}"             # set FULL=true to include venvs and caches
REMOVE_IDE="${REMOVE_IDE:-false}" # set true to remove .vscode and .idea
ROOT_SENTINEL="pyproject.toml"

say(){ printf "%s\n" "$*" >&2; }
run(){ if [ "$DRY_RUN" = "true" ]; then say "[dry-run] $*"; else eval "$@"; fi; }

# Safety, make sure at repo root
[ -f "$ROOT_SENTINEL" ] || { say "Run from repo root, missing $ROOT_SENTINEL"; exit 1; }

say "Cleaning workspace, DRY_RUN=$DRY_RUN, FULL=$FULL, REMOVE_IDE=$REMOVE_IDE"

# Always clean Python build outputs
for p in build dist .pytest_cache .coverage htmlcov pip-wheel-metadata csc_api_pipeline.egg-info; do
  [ -e "$p" ] && run "rm -rf '$p'"
done

# Bytecode, caches
run "find . -type d -name '__pycache__' -prune -exec rm -rf {} +"
run "find . -type f -name '*.py[co]' -print -delete"
run "find . -type d -name '.ipynb_checkpoints' -prune -exec rm -rf {} +"

# Keep release artefacts and docs
for keep in release_bundle docs site; do
  [ -d "$keep" ] && say "Keeping ./$keep"
done

# (Optional), deeper clean
if [ "$FULL" = "true" ]; then
  for p in .mypy_cache .ruff_cache .nox .tox .venv venv .env; do
    [ -e "$p" ] && run "rm -rf '$p'"
  done
fi

# (Optional), editor folders
if [ "$REMOVE_IDE" = "true" ]; then
  for p in .vscode .idea; do
    [ -d "$p" ] && run "rm -rf '$p'"
  done
fi

say "Done. Re-run with DRY_RUN=false to apply."
