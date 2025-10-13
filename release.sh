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

# catch unset vars/force globs(dist/*) to expand as []
set -euo pipefail
shopt -s nullglob

# read pyproject.toml ver
get_version(){ grep -E '^version\s*=\s*"' pyproject.toml | sed -E 's/.*"([^"]+)".*/\1/'; }


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

# --- validate it, fall back to computed default
if [[ ! "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "No valid semver entered, using $NEXT_TAG"
  VERSION="$NEXT_TAG"
fi

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
#
# echo "Clean old builds..."
# rm -rf build dist *.egg-info release_bundle release.zip

# --- Full clean, unified
echo "Full clean via admin/admin_bash/clean.sh..."
# preview then apply, then drop old bundles
bash admin/admin_bash/clean.sh
DRY_RUN=false FULL=true REMOVE_IDE=true bash admin/admin_bash/clean.sh
rm -rf release_bundle release.zip

# --- Version normalisation
# Users may enter "0.2.0" or "v0.2.0":
#  - Git tag will be "vX.Y.Z"
#  - pyproject.toml will be "X.Y.Z"
RAW_VERSION="$VERSION"
VERSION_TAG="v${RAW_VERSION#v}"     # ensure leading v
VERSION_PEP440="${RAW_VERSION#v}"   # strip any leading v

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

# --- Build pre_flight_checks.zip from repo-root
if [ -d pre_flight_checks ]; then
  if find pre_flight_checks -maxdepth 1 -type f -print -quit | grep -q .; then
    zip -r pre_flight_checks.zip pre_flight_checks
  else
    echo "pre_flight_checks exists but is empty, skipping zip"
  fi
fi

# --- Bundle for upload (CI assemble artifacts)
echo "Creating release zip..."
mkdir -p release_bundle
mkdir -p release_bundle/notebooks
cp dist/* release_bundle/ || true
cp README.md api_pipeline/.env.example release_bundle/ || true

# PShell API
cp api_pipeline/pshell/phase_1_api_payload.ps1 release_bundle/ || true

# SQL files
# legacy
cp sql_json_query/populate_ssd_api_data_staging_2012.sql release_bundle/ || true
# current
cp sql_json_query/populate_ssd_api_data_staging_2016sp1.sql release_bundle/ || true

# bundle notebooks into .zip also
cp -R api_pipeline/notebooks/* release_bundle/notebooks/ || true

zip -r release.zip release_bundle/

# --- Tag and push release
read -p "Push Git tag $VERSION_TAG and trigger release? (y/n): " CONFIRM
if [[ $CONFIRM == "y" ]]; then
  # --- After confirm, bump version and rebuild to match the tag
  echo "Updating pyproject.toml version to $VERSION_PEP440..."
  CURRENT_PEP440=$(grep -E '^version\s*=\s*"' pyproject.toml | sed -E 's/^version\s*=\s*"([^"]+)".*/\1/')
  if [[ "$CURRENT_PEP440" != "$VERSION_PEP440" ]]; then
    sed -i.bak "s/^version = \".*\"/version = \"$VERSION_PEP440\"/" pyproject.toml && rm -f pyproject.toml.bak
  else
    echo "pyproject.toml already at $VERSION_PEP440, no change."
  fi

  # --- Update CHANGELOG.md, manual and idempotent
CHANGELOG="CHANGELOG.md"
RELEASE_DATE="$(date -u +%Y-%m-%d)"
VERSION_HEAD="## [$VERSION_PEP440] - $RELEASE_DATE"

# bootstrap file if missing
if [ ! -f "$CHANGELOG" ]; then
cat > "$CHANGELOG" <<'EOF'
# Changelog

## [Unreleased]

EOF
fi

# only insert if version section not existing
if ! grep -q "^## \[$VERSION_PEP440\]" "$CHANGELOG"; then
tmp_chlog="$(mktemp)"
cat > "$tmp_chlog" <<EOF
$VERSION_HEAD
### Added
- 

### Changed
- 

### Fixed
- 

### Removed
- 

### Security
- 

EOF
# insert new section right after Unreleased header
awk -v RS="\n\n" -v ORS="\n\n" -v add="$(cat "$tmp_chlog")" '
  NR==1 { print; print add; next } { print }
' "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"
rm -f "$tmp_chlog"
else
  echo "CHANGELOG already contains section for $VERSION_PEP440, leaving as is"
fi


  # --- git-cliff generated changelog, commented until switch-over (tbc)
  # if ! command -v git-cliff >/dev/null 2>&1; then
  #   echo "git-cliff not found, install it or keep block commented"
  # fi
  # git-cliff --tag "$VERSION_TAG" --output CHANGELOG.md --prepend

  # Commit version and changelog combined
  git add pyproject.toml CHANGELOG.md 2>/dev/null || true
  git commit -m "chore: release $VERSION_TAG" || echo "Nothing to commit"

  # Rebuild pre_flight_checks.zip for release commit
  rm -f pre_flight_checks.zip
  zip -r pre_flight_checks.zip pre_flight_checks

  # rebuild clean artifacts with the bumped version, replace preview bundle
  rm -rf dist release_bundle release.zip
  python -m build --sdist --wheel --outdir dist
  twine check dist/*

  mkdir -p release_bundle
  mkdir -p release_bundle/notebooks
  cp dist/* release_bundle/ || true
  cp README.md api_pipeline/.env.example release_bundle/ || true
  cp api_pipeline/pshell/phase_1_api_payload.ps1 release_bundle/ || true
  cp sql_json_query/populate_ssd_api_data_staging_2012.sql release_bundle/ || true
  cp sql_json_query/populate_ssd_api_data_staging_2016sp1.sql release_bundle/ || true
  cp -R api_pipeline/notebooks/* release_bundle/notebooks/ || true
  zip -r release.zip release_bundle/

  # Create or update tag to current HEAD
  git tag "$VERSION_TAG" 2>/dev/null || git tag -f "$VERSION_TAG"
  git push origin main
  git push origin "$VERSION_TAG" --force-with-lease
  echo "Tag $VERSION_TAG pushed. GitHub Actions should build release."
else
  echo "Skipped tag push."
  CURR_VER="$(get_version)"
  echo "Preview build complete, no tag created."
  echo "Artifacts were built as v$CURR_VER, planned tag was $VERSION_TAG."
fi


# --- Summary
echo "Release bundle contents:"
ls -lh release_bundle/ || true
echo
if [[ $CONFIRM == "y" ]]; then
  echo "Release completed, tag $VERSION_TAG"
else
  echo "Preview completed, no tag created, planned tag $VERSION_TAG"
fi
echo "Output archive: release.zip"
echo "Built version: v$(get_version)"

