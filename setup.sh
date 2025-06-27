#!/bin/bash
# chmod +x setup.sh

# Install system-level dependencies
sudo apt-get update
sudo apt-get install -y graphviz graphviz-dev pkg-config

# Upgrade pip and install Python requirements
python3 -m pip install --upgrade pip
pip install -r requirements.txt

# Optionally install pygraphviz for futureproofing
pip install pygraphviz

# Install Python extension in VSCode
code --install-extension ms-python.python --force
