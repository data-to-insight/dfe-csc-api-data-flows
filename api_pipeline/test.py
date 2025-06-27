import requests
import pyodbc
from .config import SQL_CONN_STR, CLIENT_ID, CLIENT_SECRET, SCOPE, TOKEN_ENDPOINT, SUPPLIER_KEY, API_ENDPOINT_LA

def test_endpoint():
    print("Requesting token...")
    token_data = {
        "grant_type": "client_credentials",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scope": SCOPE
    }

    try:
        token_response = requests.post(TOKEN_ENDPOINT, data=token_data)
        token_response.raise_for_status()
        access_token = token_response.json().get("access_token")
        print("Token acquired.")
    except requests.exceptions.RequestException as e:
        print(f"Failed to acquire token: {e}")
        if e.response is not None:
            print("Response body:\n", e.response.text)
        return

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token}",
        "SupplierKey": SUPPLIER_KEY
    }

    print("Sending test GET request to API...")
    try:
        response = requests.get(API_ENDPOINT_LA, headers=headers)
        print(f"Status code: {response.status_code}")
        print("Response body:\n", response.text)
    except requests.exceptions.RequestException as e:
        print(f"API request failed: {e}")
        if e.response is not None:
            print("Response body:\n", e.response.text)



def test_db_connection():
    print("Testing database connection...")
    try:
        conn = pyodbc.connect(SQL_CONN_STR, timeout=5)
        print("✔ Database connection successful")
        conn.close()
    except Exception as e:
        print("✖ Database connection failed:")
        print(e)



def test_schema():
    print("Checking essential schema elements...")
    try:
        conn = pyodbc.connect(SQL_CONN_STR)
        cursor = conn.cursor()
        cursor.execute("SELECT TOP 1 * FROM ssd_api_data_staging_anon")
        columns = [column[0] for column in cursor.description]
        expected = ["id", "json_payload", "partial_json_payload", "submission_status"]
        missing = [col for col in expected if col not in columns]

        if missing:
            print(f"✖ Missing columns: {', '.join(missing)}")
        else:
            print("✔ Schema looks OK")
        conn.close()
    except Exception as e:
        print("✖ Schema check failed:")
        print(e)
