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

def test_endpoint():
    """
    Safe GET path to prove auth + outbound HTTPS/TLS works
    Uses client_credentials to obtain token and calls API_ENDPOINT_LA with GET
    Does not submit or mutate data
    Returns True/False
    """
    _print_header("API connectivity & auth (test_endpoint)")
    print("Requesting token (client_credentials)…")
    token_data = {
        "grant_type": "client_credentials",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scope": SCOPE,
    }

    try:
        token_response = requests.post(TOKEN_ENDPOINT, data=token_data, timeout=15)
        token_response.raise_for_status()
        token_json = token_response.json()
        access_token = token_json.get("access_token")
        if not access_token:
            raise RuntimeError(f"No access_token in response: {json.dumps(token_json)[:500]}")
        _ok("Token acquired")
    except requests.exceptions.RequestException as e:
        _fail("Token request", e)
        if getattr(e, "response", None) is not None:
            try:
                print("Response body:\n", e.response.text[:2000])
            except Exception:
                pass
        return False
    except Exception as e:
        _fail("Token parsing", e)
        return False

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token}",
        "SupplierKey": SUPPLIER_KEY,
    }

    print(f"Sending test GET request to: {API_ENDPOINT_LA}")
    try:
        response = requests.get(API_ENDPOINT_LA, headers=headers, timeout=15)
        print(f"Status code: {response.status_code}")
        body_preview = response.text[:2000] if isinstance(response.text, str) else str(response.content)[:2000]
        print("Response body (preview):\n", body_preview)
        if 200 <= response.status_code < 300:
            _ok("API GET reachable")
            return True
        else:
            _fail("API GET", f"Unexpected status {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        _fail("API GET", e)
        if getattr(e, "response", None) is not None:
            try:
                print("Response body:\n", e.response.text[:2000])
            except Exception:
                pass
        return False


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
    Checks essential columns exist in the staging table
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
    Composite 'smoke' run that exercises:
      - DB connectivity (SELECT 1)
      - Token acquisition
      - Harmless GET to API_ENDPOINT_LA
      - Advisory schema check (won't block install if table doesn't exist yet)
    Returns True/False and prints compact summary suitable for CI or Scheduled Tasks
    """
    _print_header("Smoke run (no data required)")
    start = time.time()
    db_ok = test_db_connection()
    api_ok = test_endpoint()
    schema_ok = test_schema()  # if the table doesn't exist yet, may return False

    overall = db_ok and api_ok and schema_ok
    duration = time.time() - start

    print("\nSummary:")
    print(f"  DB connectivity : {'PASS' if db_ok else 'FAIL'}")
    print(f"  API GET/Auth    : {'PASS' if api_ok else 'FAIL'}")
    print(f"  Schema advisory : {'PASS' if schema_ok else 'FAIL'}")
    print(f"Completed in {duration:.2f}s")

    return overall
