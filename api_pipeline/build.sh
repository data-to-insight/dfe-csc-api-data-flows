#!/bin/bash
# Needs permissions chmod +x build.sh

set -e

echo "Installing build tool..."
pip install --quiet build

echo "Cleaning previous builds..."
rm -rf dist/ build/ *.egg-info

echo "Building package..."
python -m build

echo "Done. Check the dist/ folder."
