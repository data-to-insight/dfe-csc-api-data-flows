#!/bin/bash
# release.sh — CSC API Pipeline Release Script
# v1.0 - depreciated with new slimmed down preflight + tag push helper 1.1

#
# This script automates release process for CSC API Pipeline project
# It does following steps:
#
# 1. Verifies on the 'main' branch (release safety check)
# 2. Prompts for new semantic version tag (default is last tag + patch bump)
# 3. Ensures working dir is clean (no uncommitted changes)
# 4. Fully cleans build artifacts, caches, and temp files
# 5. Updates version in `pyproject.toml` and commits change
# 6. Builds Py package (`.tar.gz` and `.whl`) - PEP 517 standards
# 7. Optionally builds Windows `.exe` using PyInstaller (if on Windows)
# 8. Creates release_bundle/ dir containing:
#    - Built distribution files
#    - README.md
#    - .env.example
#    - Optional PowerShell and SQL deployment scripts
# 9. Archives all bundled files into release.zip
# 10. Prompts for confirmation and pushes the Git tag and main branch to origin
#
# Output:
# - A clean versioned release archive at release.zip
# - Tagged version pushed to GitHub
#
# Notes:
# - Use `chmod +x release.sh` to make the script executable
# - Script intended to be run manually from Codespace(or shell)
# - release is via actions workflow/push


set -e

echo "CSC API Pipeline Release Script"
echo "----------------------------------"

# Confirm curr branch is main (safety chk)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "Releases must be made from the 'main' branch (current: $CURRENT_BRANCH)"
  exit 1
fi

# Confirm version prep
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
IFS='.' read -r MAJOR MINOR PATCH <<<"${LAST_TAG#v}"
NEXT_TAG="v$MAJOR.$MINOR.$((PATCH + 1))"

echo "Last release tag: $LAST_TAG"
read -p "Enter new version tag [default: $NEXT_TAG]: " VERSION
VERSION="${VERSION:-$NEXT_TAG}"

# Ensure clean repo
if [[ -n $(git status --porcelain) ]]; then
  echo "Uncommitted changes found. Please commit or stash before releasing."
  exit 1
fi

# Full clean
echo "Full clean..."
find . -type d -name "__pycache__" -exec rm -rf {} +
find . -type d -name "*.egg-info" -exec rm -rf {} +
find . -type f -name "*.pyc" -delete
rm -rf .pytest_cache/ .coverage .vscode/ .idea/

echo "Clean old builds..."
rm -rf build dist *.egg-info release_bundle release.zip

# Bump version in pyproject.toml
echo "Updating pyproject.toml version to $VERSION..."
sed -i.bak "s/^version = .*/version = \"${VERSION#v}\"/" pyproject.toml
rm pyproject.toml.bak

# Auto commit version bump
echo "Committing version bump..."
git add pyproject.toml
git commit -m "Bump version to $VERSION"

# Build package
echo "Build Python package..."
# python -m build
# python -m build api_pipeline --outdir dist
python -m build --sdist --wheel --outdir dist # Build from repo root (package-only discovery)

echo "Package built at dist/"

# Build Windows .exe if Windows
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


# Bundle for upload
echo "Creating release zip..."
mkdir -p release_bundle
cp dist/* release_bundle/

# # bring in other non-py|pipeline files
cp README.md api_pipeline/.env.example release_bundle/ || true
cp api_pipeline_pshell/phase_1_api_payload.ps1 release_bundle/ || true
cp api_sql_raw_json_query/populate_ssd_api_data_staging.sql release_bundle/ || true

zip -r release.zip release_bundle/

# Tag and push release
read -p "Push Git tag $VERSION and trigger release? (y/n): " CONFIRM
if [[ $CONFIRM == "y" ]]; then
  git tag "$VERSION"
  git push origin main
  git push origin "$VERSION"
  echo "Tag $VERSION pushed. Git Actions will build release."
else
  echo "Skipped tag push."
fi

# summarise outputs
echo "Release bundle contents:"
ls -lh release_bundle/
echo ""
echo "Release completed: $VERSION"
echo "Output: release.zip"
