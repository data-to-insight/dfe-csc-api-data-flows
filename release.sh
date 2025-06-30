#!/bin/bash
# chmod +x release.sh
# ./release.sh

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

# Ensure repo is clean
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
python -m build api_pipeline --outdir dist

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
cp README.md api_pipeline/.env.example release_bundle/ || true
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

echo "Done. Check Git Releases"
