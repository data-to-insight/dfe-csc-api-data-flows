# CSC API Pipeline

![Python](https://img.shields.io/badge/Python-3.10+-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Build](https://img.shields.io/github/actions/workflow/status/data-to-insight/dfe_csc_api_data_flows/build-api-pipeline.yml?branch=main)
![Release](https://img.shields.io/github/v/release/data-to-insight/dfe_csc_api_data_flows)


Lightweight tool for preparing and submitting Children's Social Care (CSC) JSON payloads to external APIs.

## Features

- Extracts and validates records from SQL Server
- Detects partial changes and builds minimal JSON payloads
- Authenticates via OAuth
- Submits payloads with retry and error logging
- Supports `.env`-based configuration

## Usage

```bash
python -m api_pipeline

## Usage

If packaged as `.exe`: csc_api_pipeline.exe


## Setup

- Copy `.env.example` to `.env`  
- Edit values (connection string, API credentials)

## Requirements

- Python 3.10+
- Dependencies listed in `pyproject.toml`

## Included

- `entry_point.py` as CLI launcher  
- `.env.example` for config template

## Build & Distribution

- PyInstaller and GitHub Actions used to generate `.exe`
- See repo root for full documentation and GitHub Pages site
