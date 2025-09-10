# api_pipeline/entry_point.py
import sys

# DEBUG
# ..(main) $ python -c "from api_pipeline.entry_point import cli; print('cli OK')"

# Dev note: Help requires manual updates
HELP_TEXT = """
CSC API Pipeline CLI

Usage:
  csc_api_pipeline run                   Run the pipeline
  csc_api_pipeline test-db-connection    Test DB connection
  csc_api_pipeline test-schema           Validate DB schema
  csc_api_pipeline run-smoke             Run smoke tests (recommended)
  csc_api_pipeline --help | -h           Show this help

Notes:
  'test-endpoint' has been deprecated (replaced by run-smoke)
"""

def cli():
    if "--help" in sys.argv or "-h" in sys.argv:
        print(HELP_TEXT)
        return

    # Defer heavy imports so --help doesn't pull config/auth/etc.
    from .main import main
    from .test import test_db_connection, test_schema, run_smoke

    command = sys.argv[1] if len(sys.argv) >= 2 else "run"

    command_map = {
        "run": main,
        "test-db-connection": test_db_connection,
        "test-schema": test_schema,
        "run-smoke": run_smoke
    }

    if command in command_map:
        command_map[command]()
    else:
        print(HELP_TEXT)

if __name__ == "__main__":
    cli()


# # Extended HELP

# HELP_TEXT = """
# CSC API Pipeline — Command Line Usage
# =====================================

# Usage:
#   csc_api_pipeline.exe [command]
#   python -m api_pipeline [command]        # run from source

# # No-data smoke check (safe diagnostics; no staging rows required)
#   csc_api_pipeline.exe smoke
#   python -m api_pipeline --mode smoke     # alias for 'smoke'


# Commands:
# ---------
#   run                   Run full API submission pipeline process
#   run-smoke             Run no-data smoke checks (DB connectivity, OAuth, harmless POST)
#   test-db-connection    Check database connection
#   test-schema           Validate required table structure/schema
#   --help, -h            Show this help message

# Aliases:
# --------
#   run-smoke             Formerly 'smoke'; now uses safe POST to test API connectivity


# Commands detail:
# ----------------

# • run
#     Execute full pipeline:
#     - Load records from database
#     - Detect changes and generate payloads
#     - Submit to API with retries and logging

# • run-smoke
#     Perform safe, no-data diagnostic run:
#     - SELECT 1 against DB (no staging-table dependency)
#     - Acquire OAuth token (client_credentials)
#     - Harmless GET to API endpoint (no mutation)
#     - Advisory schema check

# • test-db-connection
#     Connect to database using SQL_CONN_STR from .env:
#     - Confirms credentials and ODBC driver setup

# • test-schema
#     Check expected tables and columns exist:
#     - Validates schema against known list
#     - Prints status of each table

# Notes:
# ------

# - Requires `.env` file based on `.env.example`
# - Python version >= 3.10 if not using .exe
# - All logs printed to stdout (no file log)
# """

