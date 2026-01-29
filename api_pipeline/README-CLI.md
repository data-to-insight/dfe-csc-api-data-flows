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

Minimal CLI dispatcher, so can run:
```bash
python -m api_pipeline run
python -m api_pipeline test-endpoint
python -m api_pipeline test-db
python -m api_pipeline test-schema
```

If packaged as `.exe`: `csc_api_pipeline.exe [run|test-endpoint|test-db|test-schema]`



## Executable Usage

The API tool as `.exe`, can be run from the command line:

```bash
csc_api_pipeline.exe run
```

Or simply:

```bash
csc_api_pipeline.exe
```

> Default behaviour is to **run the full live pipeline** if no command is provided.

### Optional CLI Commands

The executable also supports test and debug commands:

| Command         | Description                         |
|-----------------|-------------------------------------|
| `run`           | Run main API pipeline               |
| `test-endpoint` | Check API connectivity and auth     |
| `test-db`       | Check database connection           |
| `test-schema`   | Validate schema prerequisites       |

Example usage:

```bash
csc_api_pipeline.exe test-endpoint
```

The above available towards verifying deployment or investigating issues without triggering full API submissions to DfE. All require `.env` settings for connection and credentials. 

### Help Command

See available options|supported commands from the command line:

```bash
csc_api_pipeline.exe --help 
```



## Setup

- Copy `.env.example` to `~/.env`  
- Edit values (connection string, API credentials from DfE API portal)

## Requirements

- Python 3.10+
- Dependencies listed in `pyproject.toml`

## Included

- `entry_point.py` as CLI launcher  
- `.env.example` for config template

## Build & Distribution

- PyInstaller and GitHub Actions used to generate `.exe`
- See repo root for full documentation and GitHub Pages site(tbc)
