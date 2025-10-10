#!/bin/bash
# release.sh — CSC API Pipeline Release Script
# v1.4

#
# Automates release process for CSC API Pipeline:
# 1) Safety: on main, clean working tree
# 2) Prompt for new semantic version (defaults to last tag + patch)
# 3) Clean caches/builds
# 4) Update pyproject.toml if needed and commit
# 5) Build sdist/wheel + twine check
# 6) (Linux) skip exe build; (Windows) optional PyInstaller exe build
# 7) Create release_bundle + release.zip
# 8) Tag & push to trigger Actions
#


set -e

echo "CSC API Pipeline Release Script"
echo "----------------------------------"

# --- Safety: ensure on main
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "Releases must be made from the 'main' branch (current: $CURRENT_BRANCH)"
  exit 1
fi

# --- Determine default next tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
IFS='.' read -r MAJOR MINOR PATCH <<<"${LAST_TAG#v}"
NEXT_TAG="v$MAJOR.$MINOR.$((PATCH + 1))"

echo "Last release tag: $LAST_TAG"
read -p "Enter new version tag [default: $NEXT_TAG]: " VERSION
VERSION="${VERSION:-$NEXT_TAG}"

# --- Working tree got to be clean
if [[ -n $(git status --porcelain) ]]; then
  echo "Uncommitted changes found. Please commit or stash before releasing."
  exit 1
fi

# # --- Full clean
# echo "Full clean..."
# find . -type d -name "__pycache__" -exec rm -rf {} +
# find . -type d -name "*.egg-info" -exec rm -rf {} +
# find . -type f -name "*.pyc" -delete
# rm -rf .pytest_cache/ .coverage .vscode/ .idea/

# echo "Clean old builds..."
# rm -rf build dist *.egg-info release_bundle release.zip

# --- Full clean, unified
echo "Full clean via scripts/clean.sh..."
# preview then apply, then drop old bundles
bash scripts/clean.sh
DRY_RUN=false FULL=true REMOVE_IDE=true bash scripts/clean.sh
rm -rf release_bundle release.zip


# --- Version normalisation
# Users may enter "0.2.0" or "v0.2.0":
#  - Git tag will be "vX.Y.Z"
#  - pyproject.toml will be "X.Y.Z"
RAW_VERSION="$VERSION"
VERSION_TAG="v${RAW_VERSION#v}"     # ensure leading v
VERSION_PEP440="${RAW_VERSION#v}"   # strip any leading v

# --- Bump pyproject.toml only if needed
echo "Updating pyproject.toml version to $VERSION_PEP440..."
CURRENT_PEP440=$(grep -E '^version\s*=\s*"' pyproject.toml | sed -E 's/^version\s*=\s*"([^"]+)".*/\1/')
if [[ "$CURRENT_PEP440" != "$VERSION_PEP440" ]]; then
  # On Linux/GNU sed. (macOS needs: sed -i '' ...)
  sed -i.bak "s/^version = \".*\"/version = \"$VERSION_PEP440\"/" pyproject.toml && rm -f pyproject.toml.bak
  echo "Committing version bump to $VERSION_TAG..."
  git add pyproject.toml
  git commit -m "Bump version to $VERSION_TAG"
else
  echo "pyproject.toml already at $VERSION_PEP440 — no commit needed."
fi

# --- Build package (sdist + wheel)
echo "Installing build tooling..."
python -m pip install --upgrade pip
python -m pip install build twine

echo "Build Python package..."
python -m build --sdist --wheel --outdir dist
echo "Package built at dist/:"
ls -lah dist || true

echo "Twine metadata check..."
twine check dist/*

# --- Quick smoke test in fresh venv
echo "Smoke testing wheel..."
python -m venv .relvenv
# shellcheck disable=SC1091
source .relvenv/bin/activate
pip install --upgrade pip
pip install dist/*.whl
python -c "import api_pipeline; print('Import OK:', api_pipeline.__name__)"
deactivate
rm -rf .relvenv

# --- Windows exe build (skipped on Codespaces/Linux)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
  if command -v pyinstaller &> /dev/null; then
    echo "Build Windows .exe..."
    pyinstaller --onefile api_pipeline/entry_point.py --name csc_api_pipeline
    echo "Executable created at dist/csc_api_pipeline.exe"
  else
    echo "PyInstaller not found — skipping .exe build"
  fi
else
  echo "Not on Windows — skipping .exe build"
fi


# Preflight, required files exist before bundling
missing=()

# source files that must exist
req_paths=(
  "README.md"
  "api_pipeline/.env.example"
  "api_pipeline/pshell/phase_1_api_payload.ps1"
  "api_pipeline/pshell/phase_1_api_credentials_smoke_test.ps1"
  "sql_json_query/populate_ssd_api_data_staging_2012.sql"
  "sql_json_query/populate_ssd_api_data_staging_2016sp1.sql"
  "sql_json_query/ssd_csc_api_schema_checks.sql"
  "api_pipeline/notebooks"
)

for p in "${req_paths[@]}"; do
  if [ -d "$p" ]; then
    # dir must exist and contain at least 1 file
    if ! find "$p" -type f -maxdepth 1 -print -quit | grep -q .; then
      missing+=("$p (empty directory)")
    fi
  else
    [ -e "$p" ] || missing+=("$p")
  fi
done

# built artifacts, require at least 1 wheel and 1 sdist
if ! compgen -G "dist/*.whl" >/dev/null; then
  missing+=("dist/*.whl")
fi
if ! compgen -G "dist/*.tar.gz" >/dev/null; then
  missing+=("dist/*.tar.gz")
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "Preflight failed. Missing required items:"
  for m in "${missing[@]}"; do echo " - $m"; done
  exit 1
fi

echo "Preflight passed. All required inputs are present."


# --- Bundle for upload (CI also assembles artifacts) 
echo "Creating release zip..."
mkdir -p release_bundle
mkdir -p release_bundle/notebooks
cp dist/* release_bundle/ || true
cp README.md api_pipeline/.env.example release_bundle/ || true

# PShell API
cp api_pipeline/pshell/phase_1_api_payload.ps1 release_bundle/ || true
cp api_pipeline/pshell/phase_1_api_credentials_smoke_test.ps1 release_bundle/ || true

# SQL files
# legacy
cp sql_json_query/populate_ssd_api_data_staging_2012.sql release_bundle/ || true
# current
cp sql_json_query/populate_ssd_api_data_staging_2016sp1.sql release_bundle/ || true
cp sql_json_query/ssd_csc_api_schema_checks.sql release_bundle/ || true

# bundle notebooks into .zip also
cp -R api_pipeline/notebooks/* release_bundle/notebooks/ || true



zip -r release.zip release_bundle/

# --- Tag and push release
read -p "Push Git tag $VERSION_TAG and trigger release? (y/n): " CONFIRM
if [[ $CONFIRM == "y" ]]; then
  # Create or update tag to current HEAD
  git tag "$VERSION_TAG" 2>/dev/null || git tag -f "$VERSION_TAG"
  git push origin main
  git push origin "$VERSION_TAG" --force-with-lease
  echo "Tag $VERSION_TAG pushed. GitHub Actions should build the release."
else
  echo "Skipped tag push."
fi

# --- Summary
echo "Release bundle contents:"
ls -lh release_bundle/ || true
echo
echo "Release completed: $VERSION_TAG"
echo "Output archive: release.zip"
