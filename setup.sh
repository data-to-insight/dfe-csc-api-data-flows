#!/bin/bash
# chmod +x setup.sh

set -e

# System deps for pygraphviz and related
sudo apt-get update
sudo apt-get install -y graphviz graphviz-dev pkg-config

# Upgrade
python3 -m pip install --upgrade pip

# Install project with selected extras
# Choose lean or full, depending on Codespace
pip install -e ".[dev,docs,notebooks]"

# Optional, if need it now
# pip install pygraphviz

# VS Code Python extension (Codespace usually already has)
code --install-extension ms-python.python --force || true
