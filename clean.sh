#!/bin/bash
# chmod +x clean.sh


echo "🧹 Cleaning build artifacts and cache..."

# Python cache
find . -type d -name "__pycache__" -exec rm -rf {} +
find . -type d -name "*.egg-info" -exec rm -rf {} +

# Build dirs
rm -rf build/
rm -rf dist/

# Pytest cache
rm -rf .pytest_cache/
rm -rf .coverage

# Compiled files
find . -type f -name "*.pyc" -delete

# IDE junk
rm -rf .vscode/
rm -rf .idea/

echo "✅ Clean complete."
