# --- Configurable constants ---

LA_CODE = 845
USER_SERVER = "ESLLREPORTS04V" 
USER_DATABASE = "HDM_Local"

SQL_CONN_STR = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={USER_SERVER};DATABASE={USER_DATABASE};Trusted_Connection=yes;"

TABLE_NAME = "ssd_api_data_staging_anon"
USE_PARTIAL_PAYLOAD = True

API_ENDPOINT = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1"
API_ENDPOINT_LA = f"{API_ENDPOINT}/children_social_care_data/{LA_CODE}/children"

TOKEN_ENDPOINT = "https://login.microsoftonline.com/cc0e4d98-b9f9-4d58-821f-973eb69f19b7/oauth2/v2.0/token"
CLIENT_ID = "fe28c5a9-ea4f-4347-b419-189eb761fa42" 
CLIENT_SECRET = "mR_8Q~G~Wdm2XQ2E8-_hr0fS5FKEns4wHNLtbdw7"
SCOPE = "api://children-in-social-care-data-receiver-test-1-live_6b1907e1-e633-497d-ac74-155ab528bc17/.default"
SUPPLIER_KEY = "6736ad89172548dcaa3529896892ab3f"
BATCH_SIZE = 100

REQUIRED_FIELDS = ["la_child_id", "mis_child_id", "child_details"]

ALLOWED_PURGE_BLOCKS = {
    "child_details",
    "health_and_wellbeing",
    "social_care_episodes",
    "adoption",
    "care_leavers",
    "child_and_family_assessments",
    "child_in_need_plans",
    "section_47_assessments",
    "child_protection_plans",
    "child_looked_after_placements"
    # not include care_worker_details
}

