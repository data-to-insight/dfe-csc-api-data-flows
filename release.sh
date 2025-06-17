#!/bin/bash

set -e

echo "Clean old builds..."
rm -rf build dist *.egg-info

echo "Build Python package..."
python -m build

echo "Python package built: dist/"

# .exe generation
if command -v pyinstaller &> /dev/null; then
    echo "Build Windows .exe..."
    pyinstaller --onefile api_pipeline/main.py --name csc-pipeline
    echo "Executable: dist/csc-pipeline.exe"
else
    echo "Skip .exe build — pyinstaller not found"
fi

# ZIP
echo "Zip release..."
mkdir -p release_bundle
cp dist/* release_bundle/
cp README.md .env.example release_bundle/ || true
zip -r release.zip release_bundle/

echo "done. upload 'release.zip' to Git Release"
