import os
from dotenv import load_dotenv

# Development
# Try .env first, fallback to env.txt
load_dotenv(".env") or load_dotenv("env.txt")

TABLE_NAME = os.getenv("TABLE_NAME")
USE_PARTIAL_PAYLOAD = os.getenv("USE_PARTIAL_PAYLOAD", "true").strip().lower() == "true"

# -- debug|verbose mode set in .env
DEBUG = os.getenv("DEBUG", "false").strip().lower() == "true"




# --- Required individual components ---
USER_SERVER = os.getenv("USER_SERVER")
USER_DATABASE = os.getenv("USER_DATABASE")
API_ENDPOINT = os.getenv("API_ENDPOINT")
LA_CODE = os.getenv("LA_CODE")

# --- Derived values ---
# fallback: try SQL_CONN_STR if present, else build from parts
_sql_conn_str_env = os.getenv("SQL_CONN_STR")
if _sql_conn_str_env:
    SQL_CONN_STR = _sql_conn_str_env
else:
    SQL_CONN_STR = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={USER_SERVER};DATABASE={USER_DATABASE};Trusted_Connection=yes;"

API_ENDPOINT_LA = f"{API_ENDPOINT}/children_social_care_data/{LA_CODE}/children"

# --- Other config ---
CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
SCOPE = os.getenv("SCOPE")
TOKEN_ENDPOINT = os.getenv("TOKEN_ENDPOINT")
SUPPLIER_KEY = os.getenv("SUPPLIER_KEY")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", 100))



# --- Enforced json structure elements
REQUIRED_FIELDS = [
    "la_child_id",
    "mis_child_id",
    "child_details"
]

ALLOWED_PURGE_BLOCKS = [
    "social_care_episodes",
    "child_protection_plans",
    "child_in_need_plans",
    "health_and_wellbeing",
    "care_leavers"
]



# --- Env var validation helper ---
def validate_env_vars(required_vars):
    missing = [var for var in required_vars if not os.getenv(var)]
    if missing:
        raise EnvironmentError(f"Missing required environment variables: {', '.join(missing)}")
