
#!/bin/bash
# build.sh — OPTIONAL legacy helper script
#
# script retained for lightweight, local builds of Py package
# (PEP 517 `.whl` and `.tar.gz`) but **NOT** required for full release
#
# Use `release.sh` instead for full release workflow, which includes:
# - Version bumping
# - Clean builds
# - PyInstaller `.exe` build (Windows only)
# - Git tagging
# - Packaging release_bundle and pushing to GitHub
#
# Requires: `chmod +x ./build.sh` 


set -e

echo "Installing build tool..."
pip install --quiet build

echo "Cleaning previous builds..."
rm -rf dist/ build/ *.egg-info

echo "Building package..."
python -m build

echo "Done. Check the dist/ folder."
