
# api_pipeline/entry_point.py
import sys

# DEBUG
# ..(main) $ python -c "from api_pipeline.entry_point import cli; print('cli OK')"


# Dev note: Help requ manual updates 
HELP_TEXT = """
CSC API Pipeline CLI

Usage:
  csc_api_pipeline run                   Run the pipeline
  csc_api_pipeline test-endpoint         Test API endpoint connectivity
  csc_api_pipeline test-db-connection    Test DB connection
  csc_api_pipeline test-schema           Validate DB schema
  csc_api_pipeline run-smoke             Run smoke tests
  csc_api_pipeline --help | -h           Show this help
"""

def cli():
    if "--help" in sys.argv or "-h" in sys.argv:
        print(HELP_TEXT)
        return

    # Defer heavy imports so --help doesn't pull config/auth/etc.
    from .main import main
    from .test import test_endpoint, test_db_connection, test_schema, run_smoke

    command = sys.argv[1] if len(sys.argv) >= 2 else "run"

    if command == "run":
        main()
    elif command == "test-endpoint":
        test_endpoint()
    elif command == "test-db-connection":
        test_db_connection()
    elif command == "test-schema":
        test_schema()
    elif command == "run-smoke":
        run_smoke()
    else:
        print(HELP_TEXT)


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
#   smoke                 No-data smoke checks (DB connectivity, OAuth, safe API GET)
#   test-endpoint         Check API connectivity and token authentication
#   test-db-connection    Check database connection
#   test-schema           Validate required table structure/schema
#   --help, -h            Show this help message

# Aliases:
# --------
#   --mode smoke          Same as 'smoke' (useful for parity with docs/examples)

# Commands detail:
# ----------------

# • run
#     Execute full pipeline:
#     - Load records from database
#     - Detect changes and generate payloads
#     - Submit to API with retries and logging

# • smoke
#     Perform safe, no-data diagnostic run:
#     - SELECT 1 against DB (no staging-table dependency)
#     - Acquire OAuth token (client_credentials)
#     - Harmless GET to API endpoint (no mutation)
#     - Advisory schema check

# • test-endpoint
#     Verify API connection using credentials in .env:
#     - Authenticates and sends test GET request
#     - Prints response and any issues

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

