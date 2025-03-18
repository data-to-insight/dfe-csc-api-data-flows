# Script: csc_api_stageing_data_anon_process_v0.0.0
# Author: D2I 

# 2.2 - added no future dates fix to func. moved social_worker processing into episodes in line with spec revision. 





# Extracts the contents of HDM_Local.ssd_api_data_staging (should already include hashed change tracking column data etc). 
# It takes each json record from ssd_api_data_staging.json_payload and applies an anonymisation process to it, before duplicating 
# the entire table structure and (anon)data into HDM_Local.ssd_development.ssd_api_data_staging**_anon** 
# (if this test table already exists that copy will be dropped not truncated during this process).

# !! Script cannot be run from within Git/Spaces. 
# This script must be run locally(Anaconda/Python), within trusted environmemnt with ability to connect direct to CMS DB.  

# The Live process can take a while, obv dependent on data volume and connection capacity. 
# Expect to wait ~15mins start to end. E.g. "script completed in 837.49 seconds (13.96 minutes)".

# Current process anons the following fields:
# - all id's incl. child (maintains duplication of entries with new hashed vals if same id exists, e.g. repeat workers)
# - all dates, incl. dob (random but for someone aged 10-21yrs)
# - all start and end dates (randomises start-end dates but maintains approx interval for data consistency)
# - ethnicity (random from DfE returns defined list)
# - sex (random from DfE list of 3)
# - postcode (random generated uk code)
# -- and more, a full list is dynamically output during processing for full transparency. 
# **ENSURE THAT YOU VERIFY your expectations against the output list produced during the processing**. 

# **Note regarding ID/Data security:**
# Within this process: 
#             - names are replaced entirely with fake names (or a 'SSD_PH' string value)
#             - all ID's (person and worker) are hashed (but not salted), - deterministic one-way process and  
#             - in combination with the replacement of all date values with generated dates, disabilities, and ethnicity. 
# It would be computationally impossible to regenerate any persons natural|source data from the anonimised data. 


# %pip install Faker

import pyodbc
import hashlib
import random
from datetime import datetime, timedelta
from faker import Faker 
import json
import time  
import random



# enable use of subset(s) of source data to minimise/give option on testing data in use
# Define query type: 'all', 'top_X' (e.g., 'top_100'), or 'random_X' (e.g., 'random_100')
query_mode = "all"  # Options: "all", "top_100", "random_50"



# generating random pcodes
faker = Faker("en_GB")

# db connection details
CONN_DETAILS = {
    "driver": "{SQL Server}",
    "server": "ESLLREPORTS04V",
    "database": "HDM_Local",
    "trusted_connection": "yes"
}

def normalise_keys(data):
    """
    normalise all keys in a nested dictionary or list to lowercase
    """
    if isinstance(data, dict):
        return {key.lower(): normalise_keys(value) for key, value in data.items()}
    elif isinstance(data, list):
        return [normalise_keys(item) for item in data]
    else:
        return data

def hash_id(value, max_length=36):
    """create deterministic hash truncated to max_length. Usually 36, but some at 12, 13"""
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:max_length]

def random_dob():
    """generate random DoB for someone aged 10-21 in YYYY-MM-DD format, stripped of timestamp"""
    today = datetime.today()
    years_ago = random.randint(10, 21)
    random_date = today - timedelta(days=years_ago * 365)
    return random_date.strftime("%Y-%m-%d")  # return YYYY-MM-DD format

def random_date_after(base_date, min_years=1, max_years=10):
    """
    Generate a random date that is AFTER a given base date (i.e. DoB).
    Ensures a logical timeline, e.g., preventing worker/contact related dates before birth.
    """
    base_date_obj = datetime.strptime(base_date, "%Y-%m-%d")
    days_ahead = random.randint(min_years * 365, max_years * 365)  # Random number of days ahead
    new_date = base_date_obj + timedelta(days=days_ahead)
    return new_date.strftime("%Y-%m-%d")  # Ensure YYYY-MM-DD format


def random_ethnicity():
    """generate random ethnicity from the specified list"""
    return random.choice(
        [ 
            "WBRI", "WIRI", "WIRT", "WROM", "WOTH", "MWBC", "MWBA", "MWAS", "MOTH", 
            "AIND", "APKN", "ABAN", "AOTH", "BCRB", "BAFR", "BOTH", "CHNE", "OOTH", 
            "REFU", "NOBT"
        ]
    )

def random_sex():
    """generate random sex value (m, f, u)"""
    return random.choice(["M", "F", "U"])

def random_postcode():
    """generate random uk postcode"""
    return faker.postcode()


def randomise_date_with_interval(start_date, end_date, interval_range=10):
    """Randomise dates but ensure not in future, and maintain approx days-interval - important for some relations"""
    
    # Strip time if included
    start_date = start_date.split("T")[0] if "T" in start_date else start_date
    end_date = end_date.split("T")[0] if "T" in end_date else end_date

    start_date_obj = datetime.strptime(start_date, "%Y-%m-%d")
    end_date_obj = datetime.strptime(end_date, "%Y-%m-%d")
    delta_days = (end_date_obj - start_date_obj).days

    # new start date, ensure it doesn't exceed today
    today = datetime.today()
    new_start_date = start_date_obj + timedelta(days=random.randint(-interval_range, interval_range))
    
    if new_start_date > today:
        new_start_date = today  # Cap start date to today if exceeds

    # new end date relative to new start date (maintain realistic interval)
    new_end_date = new_start_date + timedelta(days=delta_days)

    # new end date does not exceed today
    if new_end_date > today:
        new_end_date = today  # Cap end date to today

    return new_start_date.strftime("%Y-%m-%d"), new_end_date.strftime("%Y-%m-%d")




# log the run time, as it takes a while
script_start_time = time.time()

# connect to db
try:
    connection_start_time = time.time()
    connection = pyodbc.connect(
        f"DRIVER={CONN_DETAILS['driver']};SERVER={CONN_DETAILS['server']};DATABASE={CONN_DETAILS['database']};Trusted_Connection={CONN_DETAILS['trusted_connection']};"
    )
    connection_time = time.time() - connection_start_time
    print(f"connected to database successfully in {connection_time:.2f} seconds.")
except pyodbc.Error as e:
    print(f"database connection failed: {e}")
    raise

cursor = connection.cursor()


# enable use of subset(s) of source data to minimise/give option on testing data in use
try:
    # Start fetch timer
    fetch_start_time = time.time()

    # dynamically based on mode
    if query_mode == "all":
        la_child_id_list = ["129221", "102228", "102191"]
        sql_query = f"SELECT * FROM ssd_api_data_staging WHERE person_id IN ({', '.join(f"'{id}'" for id in la_child_id_list)})"



    # top x records
    elif query_mode.startswith("top_"):
        limit = int(query_mode.split("_")[1])  # numeric value from 'top_X'
        sql_query = f"SELECT TOP {limit} * FROM ssd_api_data_staging"

    # random x records
    elif query_mode.startswith("random_"):
        limit = int(query_mode.split("_")[1])  # numeric value from 'random_X'
        sql_query = f"SELECT TOP {limit} * FROM ssd_api_data_staging ORDER BY NEWID()"

    else:
        raise ValueError("Invalid query_mode. Use 'all', 'top_X', or 'random_X'.")

    cursor.execute(sql_query)
    rows = cursor.fetchall()
    column_names = [desc[0] for desc in cursor.description]  # Get column names

    # Calc fetch time
    fetch_time = time.time() - fetch_start_time
    print(f"Fetched {len(rows)} records from source ssd_api_data_staging in {fetch_time:.2f} seconds using query: {sql_query}")

except pyodbc.Error as e:
    print(f"Error fetching records: {e}")
    raise


processed_data = []

processing_start_time = time.time()

anonymised_attributes = set() # track anonymised attributes, make it explicit on run which fields have been anonymised! 

# process records in memory
for row in rows:
    record = dict(zip(column_names, row))  # row to dict for processing
    record_id = record["id"]
    person_id = record["person_id"]
    json_payload = json.loads(record["json_payload"])

    
    # normalise json keys to avoid dups (although shouldnt be any)
    json_payload = normalise_keys(json_payload)

    # Replace first_name with a random name
    json_payload["first_name"] = faker.first_name()
    json_payload["first_name"] = "SSH_PH" # TEMP - This only to make it clear the extenally sent records are fake data
    anonymised_attributes.add("first_name")

    # Replace surname with a random name
    json_payload["surname"] = faker.last_name()
    json_payload["surname"] = "SSD_PH" # TEMP - This only to make it clear the extenally sent records are fake data
    anonymised_attributes.add("surname")

    
    
    # anonymise top-level fields (child level dets)
    la_child_id = json_payload["la_child_id"]
    json_payload["la_child_id"] = hash_id(la_child_id)
    anonymised_attributes.add("la_child_id")
    
    anon_dob = random_dob()
    json_payload["date_of_birth"] = anon_dob
    anonymised_attributes.add("date_of_birth")

    json_payload["sex"] = random_sex()
    anonymised_attributes.add("sex")

    json_payload["ethnicity"] = random_ethnicity()
    anonymised_attributes.add("ethnicity")

    json_payload["postcode"] = random_postcode()
    anonymised_attributes.add("postcode")

    # Replace unique_pupil_number_unknown_reason with random val
    if "unique_pupil_number_unknown_reason" in json_payload:
        json_payload["unique_pupil_number_unknown_reason"] = random.choice(
            ["UN1", "UN2", "UN3", "UN4", "UN5", "UN6", "UN7", "UN8", "UN9", "UN10"]
        )
        anonymised_attributes.add("unique_pupil_number_unknown_reason")

    # Hash unique_pupil_number to 13 chars
    if "unique_pupil_number" in json_payload:  # note hash length field specific
        json_payload["unique_pupil_number"] = hash_id(json_payload["unique_pupil_number"], max_length=13) 
        anonymised_attributes.add("unique_pupil_number")

    # Hash former_unique_pupil_number to 13 chars
    if "former_unique_pupil_number" in json_payload:
        json_payload["former_unique_pupil_number"] = hash_id(json_payload["former_unique_pupil_number"], max_length=13)
        anonymised_attributes.add("former_unique_pupil_number")

    # anonymise nested fields
    for episode in json_payload.get("social_care_episodes", []):
        if "social_care_episode_id" in episode:
            episode["social_care_episode_id"] = hash_id(episode["social_care_episode_id"])
            anonymised_attributes.add("social_care_episode_id")

        referral_date = episode.get("referral_date")
        closure_date = episode.get("closure_date")

        # Replace referral_source with random 
        episode["referral_source"] = random.choice(
            ["1A", "1B", "1C", "1D", "2A", "2B", "3A", "3B", "3C", "3D", "3E", "3F", "4", "5A", "5B", "5C", "5D", "6", "7", "8", "9", "10"]
        )
        anonymised_attributes.add("referral_source")

        # Replace closure_reason with random
        episode["closure_reason"] = random.choice(
            ["RC1", "RC2", "RC3", "RC4", "RC5", "RC6", "RC7", "RC8", "RC9"]
        )
        anonymised_attributes.add("closure_reason")

        if referral_date and closure_date:
            episode["referral_date"], episode["closure_date"] = randomise_date_with_interval(referral_date, closure_date)
            anonymised_attributes.add("referral_date")
            anonymised_attributes.add("closure_date")

        # Anonymise child_and_family_assessments
        for assessment in episode.get("child_and_family_assessments", []):
            if "child_and_family_assessment_id" in assessment:
                assessment["child_and_family_assessment_id"] = hash_id(assessment["child_and_family_assessment_id"])
                anonymised_attributes.add("child_and_family_assessment_id")

            start_date = assessment.get("start_date")
            authorisation_date = assessment.get("authorisation_date")

            if start_date and authorisation_date:
                assessment["start_date"], assessment["authorisation_date"] = randomise_date_with_interval(start_date, authorisation_date)
                anonymised_attributes.add("start_date")
                anonymised_attributes.add("authorisation_date")

            # Replace assessment_factors with random gen list of 1-5 factor codes
            assessment["assessment_factors"] = random.sample(
                [
                    "1A", "1B", "1C", "2A", "2B", "2C", "3A", "3B", "3C", "4A", "4B", "4C",
                    "5A", "5B", "5C", "6A", "6B", "6C", "7A", "8B", "8C", "8D", "8E", "8F",
                    "9A", "10A", "11A", "12A", "13A", "14A", "15A", "16A", "17A", "18B",
                    "18C", "19B", "19C", "20", "21", "22A", "23A", "24A"
                ],
                random.randint(1, 5)  
            )
            anonymised_attributes.add("assessment_factors")

    
        # Anonymise social_workers
        # for worker in json_payload.get("care_worker_details", []): # previous un-nested block
        for worker in episode.get("care_worker_details", []):
            if "worker_id" in worker:

                print(f"Before: {worker}") # debug
                
                worker["worker_id"] = hash_id(worker["worker_id"], max_length=12)
                anonymised_attributes.add("social_worker_id")
    
                worker_start_date = worker.get("start_date", "").split("T")[0]
                worker_end_date = worker.get("end_date", "").split("T")[0]
    
            # If both start and end dates exist, randomise them while maintaining their interval
            if worker_start_date and worker_end_date:
                worker["start_date"], worker["end_date"] = randomise_date_with_interval(worker_start_date, worker_end_date)
                anonymised_attributes.add("social_worker_start_date")
                anonymised_attributes.add("social_worker_end_date")
    
            # If start date exists, randomise but ensure it's after anon DoB
            elif worker_start_date:
                worker["start_date"] = random_date_after(anon_dob, min_years=1, max_years=18) 
                anonymised_attributes.add("social_worker_start_date")

            print(f"After: {worker}") # debug

        
        # Anonymise child_in_need_plans
        for plan in episode.get("child_in_need_plans", []):
            start_date = plan.get("start_date", "").split("T")[0]
            end_date = plan.get("end_date", "").split("T")[0]

            if start_date and end_date:
                plan["start_date"], plan["end_date"] = randomise_date_with_interval(start_date, end_date)
                anonymised_attributes.add("start_date")
                anonymised_attributes.add("end_date")

                
        # Anonymise health_and_wellbeing
        for wellbeing in episode.get("health_and_wellbeing", []):
            if "sdq_date" in wellbeing:
                wellbeing["sdq_date"] = random_date_after(anon_dob, min_years=5, max_years=20)  # 5-20 years after birth
                anonymised_attributes.add("sdq_date")

        # Anonymise care_leavers
        for care_leaver in episode.get("care_leavers", []):
            if "contact_date" in care_leaver:
                care_leaver["contact_date"] = random_date_after(anon_dob, min_years=14, max_years=30)  # 14-30 years after birth
                anonymised_attributes.add("contact_date")

            if "activity" in care_leaver:
                care_leaver["activity"] = random.choice(["F1", "P1", "F2", "P2", "F4", "P4", "F5", "P5", "G4", "G5", "G6"])
                anonymised_attributes.add("activity")

            if "accommodation" in care_leaver:
                care_leaver["accommodation"] = random.choice(["B", "C", "D", "E", "G", "H", "K", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"])
                anonymised_attributes.add("accommodation")

        
    # Anonymise disabilities if exist
    if "disabilities" in json_payload:
        for disability in json_payload["disabilities"]:
            if "disability" in disability:
                disability["disability"] = random.choice(
                    ["NONE", "MOB", "HAND", "PC", "INC", "COMM", "LD", "HEAR", "VIS", "BEH", "CON", "AUT", "DDA"]
                )
                anonymised_attributes.add("disability")

            
            
    # update json_payload and retain all other fields
    record["person_id"] = hash_id(person_id) if person_id else None
    record["json_payload"] = json.dumps(json_payload)
    processed_data.append(tuple(record.values()))

# Output anonymised attributes (visual check to know what's being/been done)
print("\nImportant: anonymising <only> these attributes:")
for attribute in sorted(anonymised_attributes):
    print(f"- {attribute}")


    
processing_time = time.time() - processing_start_time
print(f"\n\nprocessed-anon extracted records in {processing_time:.2f} seconds.")
print(f"\nsending back to the ssd_api_data_staging_anon table on db now... ")

# create new ANON table fo api tests to hit
try:
    table_creation_start_time = time.time()
    # Note: The below table def differs to the source one, and therefore the following should not be pre-set:
    # (auto)PK value, any default status values should not be defined as all later copied accross.
    cursor.execute("DROP TABLE IF EXISTS ssd_api_data_staging_anon")
    cursor.execute("""
        CREATE TABLE ssd_api_data_staging_anon (
            id                      INT PRIMARY KEY,          
            person_id               NVARCHAR(48) NULL,              -- Link value (_person_id or equivalent)
            previous_json_payload   NVARCHAR(MAX) NULL,             -- Enable sub-attribute purge tracking
            json_payload            NVARCHAR(MAX) NULL,             -- JSON data payload
            partial_json_payload    NVARCHAR(MAX) NULL,         -- Reductive JSON data payload
            previous_hash           BINARY(32) NULL,                -- Previous hash of JSON payload
            current_hash            BINARY(32) NULL,                -- Current hash of JSON payload
            row_state               NVARCHAR(10) NULL,              -- Record state: New, Updated, Deleted, Unchanged
            last_updated            DATETIME NULL,                  -- Last update timestamp
            submission_status       NVARCHAR(50) NULL,              -- Status: pending, sent, error
            api_response            NVARCHAR(MAX) NULL,             -- API response or error messages
            submission_timestamp    DATETIME                        -- Timestamp on API submission
        )
    """)
    
    
    

    
    
    table_creation_time = time.time() - table_creation_start_time
    print(f"created new table ssd_api_data_staging_anon ready for data insertion in {table_creation_time:.2f} seconds.")
    print(f"\npreparing data for insertion now...")

except pyodbc.Error as e:
    print(f"error creating ssd_api_data_staging_anon table: {e}")
    raise

# bulk insert processed data
try:
    insert_start_time = time.time()
    column_placeholders = ", ".join(["?"] * len(column_names))
    insert_query = f"INSERT INTO ssd_api_data_staging_anon ({', '.join(column_names)}) VALUES ({column_placeholders})"
    cursor.executemany(insert_query, processed_data)
    insert_time = time.time() - insert_start_time
    print(f"inserted all processed records into ssd_api_data_staging_anon in {insert_time:.2f} seconds.")
except pyodbc.Error as e:
    print(f"error inserting data: {e}")
    raise

# commit db changes
commit_start_time = time.time()
connection.commit()
commit_time = time.time() - commit_start_time
print(f"\n\ncommitted all changes in {commit_time:.2f} seconds.")

# close connection
cursor.close()
connection.close()
print("database connection closed.")

# End timer
script_end_time = time.time()
total_time = script_end_time - script_start_time
total_time_minutes = total_time / 60

print(f"\nscript completed in {total_time:.2f} seconds ({total_time_minutes:.2f} minutes).")
