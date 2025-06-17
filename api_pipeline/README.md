# CSC API Pipeline

This tool prepares and submits partial or full JSON payloads to the DfE Children’s Social Care API. It handles OAuth authentication, payload generation, diffing, batching, retries, and SQL Server logging.

## Structure

- `main.py`: CLI entry point
- `payload.py`: JSON diff logic
- `db.py`: SQL Server interactions
- `api.py`: API batching and retry logic
- `config.py`: Environment-based settings
- `utils.py`: Timing/memory decorators
- `run_pipeline.ipynb`: Jupyter dev entry point

## Setup

Install dependencies:

```bash
pip install -r requirements.txt
