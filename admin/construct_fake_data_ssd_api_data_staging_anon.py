import json
import pyodbc
import uuid
import datetime
import random
import string
import copy

def generate_random_id(original):
    """Generate a new random string of the same length as the original."""
    pool = string.ascii_letters + string.digits
    return ''.join(random.choices(pool, k=len(original)))

def update_ids(obj):
    """
    Recursively update any dictionary key that ends with '_id'
    or is exactly 'unique_pupil_number' with a new random id.
    """
    if isinstance(obj, dict):
        for key, value in obj.items():
            if isinstance(value, str) and (key.endswith("_id") or key == "unique_pupil_number"):
                obj[key] = generate_random_id(value)
            elif isinstance(value, (dict, list)):
                update_ids(value)
    elif isinstance(obj, list):
        for item in obj:
            update_ids(item)

def generate_records(sample_record, num_records):
    """
    Duplicate the sample record num_records times.
    Each duplicate is deep-copied and then its id fields are updated.
    """
    records = []
    for _ in range(num_records):
        new_record = copy.deepcopy(sample_record)
        update_ids(new_record)
        records.append(new_record)
    return records

def insert_into_new_table(records, conn):
    """
    Drop the table if it exists, create it with the new definition,
    and insert each record with auto-generated id, person_id,
    and default values for other fields. The generated person_id is also
    assigned to the "la_child_id" field within the JSON payload.
    """
    import json, uuid, datetime
    cursor = conn.cursor()
    
    # Drop the table if it exists and create it with the new schema.
    cursor.execute("DROP TABLE IF EXISTS ssd_api_data_staging_anon")
    cursor.execute("""
        CREATE TABLE ssd_api_data_staging_anon (
            id                      INT PRIMARY KEY,          
            person_id               NVARCHAR(48) NULL,              -- Link value (_person_id or equivalent)
            previous_json_payload   NVARCHAR(MAX) NULL,             -- Enable sub-attribute purge tracking
            json_payload            NVARCHAR(MAX) NULL,             -- JSON data payload
            partial_json_payload    NVARCHAR(MAX) NULL,             -- Reductive JSON data payload
            previous_hash           BINARY(32) NULL,                -- Previous hash of JSON payload
            current_hash            BINARY(32) NULL,                -- Current hash of JSON payload
            row_state               NVARCHAR(10) NULL,              -- Record state: New, Updated, Deleted, Unchanged
            last_updated            DATETIME NULL,                  -- Last update timestamp
            submission_status       NVARCHAR(50) NULL,              -- Status: pending, sent, error
            api_response            NVARCHAR(MAX) NULL,             -- API response or error messages
            submission_timestamp    DATETIME                        -- Timestamp on API submission
        )
    """)
    conn.commit()
    
    # Prepare the insert statement.
    insert_sql = """
        INSERT INTO ssd_api_data_staging_anon (
            id,
            person_id,
            previous_json_payload,
            json_payload,
            partial_json_payload,
            previous_hash,
            current_hash,
            row_state,
            last_updated,
            submission_status,
            api_response,
            submission_timestamp
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    
    now = datetime.datetime.now()
    for i, record in enumerate(records, start=1):
        record_id = i  # sequential id
        
        # Generate a UUID without hyphens (32 characters) and use it as person_id.
        person_id = uuid.uuid4().hex
        
        # Override the "la_child_id" field in the JSON with the generated person_id.
        record["la_child_id"] = person_id
        
        previous_json_payload = None
        json_payload = json.dumps(record)
        partial_json_payload = None
        previous_hash = None
        current_hash = None
        row_state = 'new'
        last_updated = now
        submission_status = 'pending'
        api_response = None
        submission_timestamp = now
        
        cursor.execute(insert_sql, 
                       record_id,
                       person_id,
                       previous_json_payload,
                       json_payload,
                       partial_json_payload,
                       previous_hash,
                       current_hash,
                       row_state,
                       last_updated,
                       submission_status,
                       api_response,
                       submission_timestamp)
    conn.commit()
    print(f"{len(records)} records inserted into ssd_api_data_staging_anon.")


def query_new_table(conn_str):
    """Query and print all records from the ssd_api_data_staging_anon table."""
    conn_str = conn_str
    
    try:
        conn = pyodbc.connect(conn_str)
        print("Database connection successful.")
    except Exception as e:
        print("Error connecting to database:", e)
        return

    cursor = conn.cursor()
    query_sql = "SELECT id, person_id, json_payload, row_state, last_updated, submission_status, submission_timestamp FROM ssd_api_data_staging_anon"
    cursor.execute(query_sql)
    
    rows = cursor.fetchall()
    for row in rows:
        # Unpack row values
        rec_id, person_id, json_payload, row_state, last_updated, submission_status, submission_timestamp = row
        record = json.loads(json_payload)
        print(f"ID: {rec_id}, PersonID: {person_id}, RowState: {row_state}, LastUpdated: {last_updated}, SubmissionStatus: {submission_status}, SubmissionTimestamp: {submission_timestamp}")
        print("JSON Payload:")
        print(record)
        print("-" * 60)
    
    conn.close()

def main():
    # Define the sample JSON record
    # updated 081225
    sample_json_str = """
    {
        "la_child_id" : "Child1234",
        "mis_child_id" : "Supplier-Child-1234",
        "child_details" : {
            "unique_pupil_number" : "ABC0123456789",
            "former_unique_pupil_number" : "DEF0123456789",
            "unique_pupil_number_unknown_reason" : "UN1",
            "first_name" : "John",
            "surname" : "Doe",
            "date_of_birth" : "2022-06-14",
            "expected_date_of_birth" : "2022-06-14",
            "sex" : "M",
            "ethnicity" : "WBRI",
            "disabilities" : [
                "HAND",
                "VIS"
            ],
            "postcode" : "AB12 3DE",
            "uasc_flag" : true,
            "uasc_end_date" : "2022-06-14",
            "purge" : false
        },
        "health_and_wellbeing" : {
            "sdq_assessments" : [{
                "date" : "2022-06-14",
                "score" : 20
            }],
            "purge" : false
        },
        "social_care_episodes" : [{
            "social_care_episode_id" : "ABC123456",
            "referral_date" : "2022-06-14",
            "referral_source" : "1C",
            "referral_no_further_action_flag" : false,
            "care_worker_details" : [{
                "worker_id" : "ABC123",
                "start_date" : "2022-06-14",
                "end_date" : "2022-06-14"
            }],
            "child_and_family_assessments" : [{
                "child_and_family_assessment_id" : "ABC123456",
                "start_date" : "2022-06-14",
                "authorisation_date" : "2022-06-14",
                "factors" : [
                    "1C",
                    "4A"
                ],
                "purge" : false
            }],
            "child_in_need_plans": [{
                "child_in_need_plan_id": "ABC123456",
                "start_date": "2022-06-14",
                "end_date": "2022-06-14",
                "purge" : false
            }],
            "section_47_assessments": [{
                "section_47_assessment_id": "ABC123456",
                "start_date": "2022-06-14",
                "icpc_required_flag": true,
                "icpc_date": "2022-06-14",
                "end_date": "2022-06-14",
                "purge" : false
            }],
            "child_protection_plans": [{
                "child_protection_plan_id": "ABC123456",
                "start_date": "2022-06-14",
                "end_date": "2022-06-14",
                "purge" : false
            }],
            "child_looked_after_placements": [{
                "child_looked_after_placement_id": "ABC123456",
                "start_date": "2022-06-14",
                "start_reason": "S",
                "placement_type": "K1",
                "postcode": "AB12 3DE",
                "end_date": "2022-06-14",
                "end_reason": "E3",
                "change_reason": "CHILD",
                "purge" : false
            }],
            "adoption" : {
                "initial_decision_date" : "2022-06-14",
                "matched_date" : "2022-06-14",
                "placed_date" : "2022-06-14",
                "purge" : false
            },
            "care_leavers" : {
                "contact_date" : "2022-06-14",
                "activity" : "F2",
                "accommodation" : "D",
                "purge" : false
            },
            "closure_date": "2022-06-14",
            "closure_reason": "RC7",
            "purge" : false
        }],
        "purge" : false
    }
    """

    sample_record = json.loads(sample_json_str)

    # Generate duplicated records (with unique id values updated within the JSON payloads).
    num_records = 355  # Adjust as needed.
    records = generate_records(sample_record, num_records)

    server = "ESLLREPORTS04V"
    database = "HDM_Local"
    trusted_connection = "yes"
    driver = '{ODBC Driver 17 for SQL Server}' # or {SQL Server}

    conn_str = f"DRIVER={driver};SERVER={server};DATABASE={database};Trusted_Connection={trusted_connection}"
    
    try:
        conn = pyodbc.connect(conn_str)
        print("Database connection successful.")
    except Exception as e:
        print("Error connecting to database:", e)
        return

    # Insert the records into the new table.
    insert_into_new_table(records, conn)
    
    # Optionally, query the table to see the inserted records.
    query_new_table(conn_str)
    
    conn.close()

if __name__ == '__main__':
    main()






##### Reset data block

## reset flag values afer a run of internal/external api testing

import pyodbc

def reset_table_fields():
    server = "ESLLREPORTS04V"
    database = "HDM_Local"
    trusted_connection = "yes"
    driver = '{ODBC Driver 17 for SQL Server}' # or {SQL Server}

    conn_str = f"DRIVER={driver};SERVER={server};DATABASE={database};Trusted_Connection={trusted_connection}"
    
    try:
        conn = pyodbc.connect(conn_str)
        print("Database connection successful.")
    except Exception as e:
        print("Error connecting to database:", e)
        return

    cursor = conn.cursor()
    
    # Update statement to reset specified fields.
    update_sql = """
    UPDATE ssd_api_data_staging_anon
    SET row_state = 'new',
        submission_status = 'pending',
        last_updated = GETDATE(),
        api_response = NULL
    """
    cursor.execute(update_sql)
    conn.commit()
    print("Table fields reset successfully.")
    
    conn.close()

if __name__ == "__main__":
    reset_table_fields()

### end reset data block




## reset flag values afer a run of internal/external api testing

import pyodbc

def reset_table_fields():
    server = "ESLLREPORTS04V"
    database = "HDM_Local"
    trusted_connection = "yes"
    driver = '{ODBC Driver 17 for SQL Server}' # or {SQL Server}

    conn_str = f"DRIVER={driver};SERVER={server};DATABASE={database};Trusted_Connection={trusted_connection}"
    
    try:
        conn = pyodbc.connect(conn_str)
        print("Database connection successful.")
    except Exception as e:
        print("Error connecting to database:", e)
        return

    cursor = conn.cursor()
    
    # Update statement to reset specified fields.
    update_sql = """
    UPDATE ssd_api_data_staging_anon
    SET row_state = 'new',
        submission_status = 'pending',
        last_updated = GETDATE(),
        api_response = NULL
    """
    cursor.execute(update_sql)
    conn.commit()
    print("Table fields reset successfully.")
    
    conn.close()

if __name__ == "__main__":
    reset_table_fields()

### end reset data block




#### query current data in staging_anon

import pyodbc
import json

def query_table():
    
    server = "ESLLREPORTS04V"
    database = "HDM_Local"
    trusted_connection = "yes"
    driver = '{ODBC Driver 17 for SQL Server}' # or {SQL Server}

    conn_str = f"DRIVER={driver};SERVER={server};DATABASE={database};Trusted_Connection={trusted_connection}"
    
    try:
        conn = pyodbc.connect(conn_str)
        print("Database connection successful.")
    except Exception as e:
        print("Error connecting to database:", e)
        return

    cursor = conn.cursor()
    
    # Query the table.
    query_sql = "SELECT json_payload FROM ssd_api_staging_data_anon"
    cursor.execute(query_sql)
    
    # Fetch all rows from the query.
    rows = cursor.fetchall()
    
    # Process each row: convert the JSON string to a Python dictionary and print.
    for row in rows:
        json_str = row[0]
        record = json.loads(json_str)
        print(record)
    
    conn.close()

if __name__ == '__main__':
    query_table()


#### end query current data in staging_anon