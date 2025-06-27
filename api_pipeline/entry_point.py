import sys
from .main import main
from .tests import test_endpoint, test_db_connection, test_schema


# Dev note: Help requires manual updates. 
HELP_TEXT = """
CSC API Pipeline — Command Line Usage
=====================================

Available commands:
-------------------

• run
    Execute full pipeline:
    - Load records from database
    - Detect changes and generate payloads
    - Submit to API with retries and logging

• test-endpoint
    Verify API connection using credentials in .env:
    - Authenticates and sends test GET request
    - Prints response and any issues

• test-db-connection
    Connect to database using SQL_CONN_STR from .env:
    - Confirms credentials and ODBC driver setup

• test-schema
    Check expected tables and columns exist:
    - Validates schema against known list
    - Prints status of each table

Usage examples:
---------------

    csc_api_pipeline.exe run
    csc_api_pipeline.exe test-endpoint
    csc_api_pipeline.exe test-db-connection
    csc_api_pipeline.exe test-schema
    csc_api_pipeline.exe --help

Notes:
------

- Requires `.env` file based on `.env.example`
- Python version >= 3.10 if not using .exe
- All logs printed to stdout (no file log)
"""


def cli():
    if "--help" in sys.argv or "-h" in sys.argv:
        print(HELP_TEXT)
        return

    if len(sys.argv) < 2:
        command = "run"  # default to run if no arg
    else:
        command = sys.argv[1]

    if command == "run":
        main()
    elif command == "test-endpoint":
        test_endpoint()
    elif command == "test-db":
        test_db_connection()
    elif command == "test-schema":
        test_schema()
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    cli()
