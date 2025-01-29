#!/usr/bin/env python
# coding: utf-8

# !! Cannot be run from Git/Spaces. Must be run locally within such as Anaconda/Python as requ' connect direct to CMS DB !! 


# Extracts the contents of HDM_Local.ssd_api_data_staging (should already include hashed change tracking column data etc). Takes each json record from ssd_api_data_staging.json_payload and applies an anonymisation process to it. 
# 
# The process takes a while. 
# Expect to wait ~15mins start to end. E.g. "script completed in 837.49 seconds (13.96 minutes)".
# Better to reduce row count in source tables first!! 
# 
# Current process anons the following fields:
# - all id's incl. child (maintains duplication of entries with new hashed vals if same id exists, e.g. workers)
# - all dates, incl. dob (random but for someone aged 10-21yrs)
# - all start and end dates (randomises start-end dates but maintains approx relationship for data consistency)
# - ethnicity (random from DfE list)
# - sex (random from DfE list of 3)
# - postcode (random generated uk code)
# -- and more, **ENSURE THAT YOU VERIFY your expectations against the output list produced during the processing**. 
# 
# **Note regarding ID/Data security:**
# Within this process: 
# #             - names are replaced entirely with fake names. 
# #             - all ID's (person and worker) are hashed (but not salted), - deterministic one-way process and  
# #             - in combination with the replacement of all date values with generated dates, disabilities, and ethnicity. 
# It would be computationally impossible to regenerate any persons natural|source data from the anonimised data. 

# In[ ]:


import pyodbc
import hashlib
import random
from datetime import datetime, timedelta
from faker import Faker
import json
import time  

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
    """generate a random date of birth for someone aged 10-21 in YYYY-MM-DD format, stripping timestamps"""
    today = datetime.today()
    years_ago = random.randint(10, 21)
    random_date = today - timedelta(days=years_ago * 365)
    return random_date.strftime("%Y-%m-%d")  # return YYYY-MM-DD format


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
    """randomise dates but maintain approx days-interval"""
    
    # Strip time if included
    start_date = start_date.split("T")[0] if "T" in start_date else start_date
    end_date = end_date.split("T")[0] if "T" in end_date else end_date

    start_date_obj = datetime.strptime(start_date, "%Y-%m-%d")
    end_date_obj = datetime.strptime(end_date, "%Y-%m-%d")
    delta_days = (end_date_obj - start_date_obj).days

    new_start_date = start_date_obj + timedelta(days=random.randint(-interval_range, interval_range))
    new_end_date = new_start_date + timedelta(days=delta_days)
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

# fetch all records
try:
    fetch_start_time = time.time()
    cursor.execute("SELECT * FROM ssd_api_data_staging")
    rows = cursor.fetchall()
    column_names = [desc[0] for desc in cursor.description]  # Get column names
    fetch_time = time.time() - fetch_start_time
    print(f"fetched {len(rows)} records from source ssd_api_data_staging in {fetch_time:.2f} seconds.")
except pyodbc.Error as e:
    print(f"error fetching records: {e}")
    raise

processed_data = []

processing_start_time = time.time()

anonymised_attributes = set() # set to track anonymised attributes

# process records in memory
for row in rows:
    record = dict(zip(column_names, row))  # Convert row to dict for easier processing
    record_id = record["id"]
    person_id = record["person_id"]
    json_payload = json.loads(record["json_payload"])

    
    # normalise json keys to avoid dups (although shouldnt be any)
    json_payload = normalise_keys(json_payload)

    # Replace first_name with a random name
    json_payload["first_name"] = faker.first_name()
    anonymised_attributes.add("first_name")

    # Replace surname with a random name
    json_payload["surname"] = faker.last_name()
    anonymised_attributes.add("surname")

    # anonymise top-level fields (child level dets)
    la_child_id = json_payload["la_child_id"]
    json_payload["la_child_id"] = hash_id(la_child_id)
    anonymised_attributes.add("la_child_id")

    json_payload["date_of_birth"] = random_dob()
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
                wellbeing["sdq_date"] = random_dob()  # Use random_dob for simplicity or modify for specific range
                anonymised_attributes.add("sdq_date")

        # Anonymise care_leavers
        for care_leaver in episode.get("care_leavers", []):
            if "contact_date" in care_leaver:
                care_leaver["contact_date"] = random_dob()  # Randomise date
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

    # Anonymise social_workers
    for worker in json_payload.get("social_workers", []):
        if "worker_id" in worker:
            worker["worker_id"] = hash_id(worker["worker_id"], max_length=12) # note hash length field specific
            anonymised_attributes.add("worker_id")

    # update json_payload and retain all other fields
    record["person_id"] = hash_id(person_id) if person_id else None
    record["json_payload"] = json.dumps(json_payload)
    processed_data.append(tuple(record.values()))

# Output anonymised attributes (visual check to know what's being/been done)
print("\nImportant: anonymising only these attributes:")
for attribute in sorted(anonymised_attributes):
    print(f"- {attribute}")


    
processing_time = time.time() - processing_start_time
print(f"\n\nprocessed-anon extracted records in {processing_time:.2f} seconds.")
print(f"\nsending back to the ssd_api_data_staging_anon table on db now...\n ")

# create new ANON table fo api tests to hit
try:
    table_creation_start_time = time.time()
    cursor.execute("DROP TABLE IF EXISTS ssd_api_data_staging_anon")
    cursor.execute("""
        CREATE TABLE ssd_api_data_staging_anon (
            id INT PRIMARY KEY,
            person_id NVARCHAR(48) NULL,
            json_payload NVARCHAR(MAX) NOT NULL,
            current_hash BINARY(32) NULL,
            previous_hash BINARY(32) NULL,
            submission_status NVARCHAR(50) DEFAULT 'Pending',
            submission_timestamp DATETIME DEFAULT GETDATE(),
            api_response NVARCHAR(MAX) NULL,
            row_state NVARCHAR(10) DEFAULT 'new',
            last_updated DATETIME DEFAULT GETDATE()
        )
    """)
    table_creation_time = time.time() - table_creation_start_time
    print(f"created new table ssd_api_data_staging_anon ready for data insertion in {table_creation_time:.2f} seconds.")
    print(f"preparing data for insertion now...")

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
print(f"committed all changes in {commit_time:.2f} seconds.")

# close connection
cursor.close()
connection.close()
print("database connection closed.")

# End timer
script_end_time = time.time()
total_time = script_end_time - script_start_time
total_time_minutes = total_time / 60

print(f"script completed in {total_time:.2f} seconds ({total_time_minutes:.2f} minutes).")


# In[ ]:




