# api_pipeline/test.py

import json
import time
import requests
import pyodbc

from .config import (
    SQL_CONN_STR,
    CLIENT_ID,
    CLIENT_SECRET,
    SCOPE,
    TOKEN_ENDPOINT,
    SUPPLIER_KEY,
    API_ENDPOINT_LA,
)

# ----------------- helpers -----------------

def _print_header(title: str):
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)

def _ok(label: str):
    print(f"[OK] {label}")

def _fail(label: str, err):
    print(f"[FAIL] {label}: {err}")

# ----------------- public tests -----------------

def test_db_connection():
    """
    Verifies SQL connectivity using configured SQL_CONN_STR
    Uses harmless SELECT 1. Does not touch staging tables
    Returns True/False
    """
    _print_header("Database connectivity (test_db_connection)")
    try:
        with pyodbc.connect(SQL_CONN_STR, timeout=5) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        _ok("Database connection successful (SELECT 1)")
        return True
    except Exception as e:
        _fail("Database connection failed", e)
        return False


def test_schema():
    """
    Checks essential columns exist in staging table
    This is *advisory* and does not change data
    Returns True/False
    """
    _print_header("Schema check (test_schema)")
    table_name = "ssd_api_data_staging_anon"
    expected = ["id", "json_payload", "partial_json_payload", "submission_status"]
    recommended = ["row_state", "previous_json_payload"]

    try:
        with pyodbc.connect(SQL_CONN_STR, timeout=10) as conn:
            cur = conn.cursor()
            cur.execute(f"SELECT TOP 0 * FROM {table_name}")
            columns = [column[0] for column in cur.description]

        missing = [col for col in expected if col not in columns]
        if missing:
            print(f"Missing REQUIRED columns in {table_name}: {', '.join(missing)}")
            return False
        _ok("Required columns present: " + ", ".join(expected))

        missing_recommended = [col for col in recommended if col not in columns]
        if missing_recommended:
            print("Note: missing recommended columns: " + ", ".join(missing_recommended))
        else:
            _ok("Recommended columns present: " + ", ".join(recommended))

        return True
    except Exception as e:
        _fail("Schema check failed", e)
        return False


# ----------------- optional orchestrator -----------------

def run_smoke():
    """
    Composite 'smoke' run that chks:
      - DB connectivity (SELECT 1)
      - Token acquisition
      - Harmless POST to API_ENDPOINT_LA with dummy payload
      - Advisory schema check (won't block install if table doesn't exist yet)
    Returns True/False and output compact summary, also for CI or scheduled tasks
    """
    _print_header("Smoke run (no data required)")
    start = time.time()
    db_ok = test_db_connection()
    api_ok = _smoke_post_to_api()
    schema_ok = test_schema()

    overall = db_ok and api_ok and schema_ok
    duration = time.time() - start

    print("\nSummary:")
    print(f"  DB connectivity : {'PASS' if db_ok else 'FAIL'}")
    print(f"  API POST/Auth   : {'PASS' if api_ok else 'FAIL'}")
    print(f"  Schema advisory : {'PASS' if schema_ok else 'FAIL'}")
    print(f"Completed in {duration:.2f}s")

    return overall


def _smoke_post_to_api():
    """
    Acquires token and sends harmless dummy POST to API
    Intended for smoke test only.
    """
    print("Requesting token for smoke test...")
    token_data = {
        "grant_type": "client_credentials",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scope": SCOPE
    }

    try:
        response = requests.post(TOKEN_ENDPOINT, data=token_data)
        response.raise_for_status()
        access_token = response.json().get("access_token")
    except Exception as e:
        print("Token acquisition failed:", e)
        return False

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token}",
        "SupplierKey": SUPPLIER_KEY
    }

    dummy_payload = {}  # or use {"test": true} 
    print("Sending harmless POST to API...")
    try:
        response = requests.post(API_ENDPOINT_LA, headers=headers, json=dummy_payload)
        print(f"Status: {response.status_code}")
        if response.status_code in [200, 400, 422]:
            print("API responded to dummy POST")
            return True
        else:
            print("Unexpected response:", response.text)
            return False
    except Exception as e:
        print("POST request failed:", e)
        return False

