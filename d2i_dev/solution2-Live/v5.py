# Script: csc_api_stageing_data_anon_process_v0.0.0
# Author: D2I 



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
import pandas as pd 


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


def extract_all_keys(json_obj, parent_key=""):
    """Recursively extract all keys from nested JSON structure, used to cross-check what has/has not been anonymised"""
    keys = set()
    
    if isinstance(json_obj, dict):
        for key, value in json_obj.items():
            full_key = f"{parent_key}.{key}" if parent_key else key
            keys.add(full_key)
            keys.update(extract_all_keys(value, full_key))  # Recursively get keys

    elif isinstance(json_obj, list):
        for item in json_obj:
            keys.update(extract_all_keys(item, parent_key))  # Recursively handle lists
    
    return keys


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


def normalise_dob(dob_str):
    """
    Return a realistic anonymised DoB.
    If the input is a known placeholder (like '1900-01-01'), generate a new one.
    """
    if dob_str in ["1900-01-01", "", None]:
        return generate_random_dob()
    return dob_str

def generate_random_dob():
    """
    Generate a realistic random date of birth for a person aged between 10 and 21 years.
    Returned as a string in YYYY-MM-DD format.
    """
    today = datetime.today()
    years_ago = random.uniform(10, 21)  # Float for better randomness
    random_days = int(years_ago * 365.25)
    random_date = today - timedelta(days=random_days)
    return random_date.strftime("%Y-%m-%d")


def random_date_after(base_date, min_years=1, max_years=10):
    """
    Generate a random date that is AFTER a given base date (i.e. DoB).
    Ensures a logical timeline, e.g., preventing worker/contact related dates before birth.
    """
    base_date_obj = parse_date_safe(base_date)  # Use safe parser
    days_ahead = random.randint(min_years * 365, max_years * 365)
    new_date = base_date_obj + timedelta(days=days_ahead)
    return new_date.strftime("%Y-%m-%d")


def parse_date_safe(date_input):
    """Convert various input formats to datetime object."""
    if isinstance(date_input, datetime):
        return date_input
    elif isinstance(date_input, str):
        date_str = date_input.split("T")[0]  # Strip time if present
        try:
            return datetime.strptime(date_str, "%Y-%m-%d")
        except ValueError:
            raise ValueError(f"Unrecognised date string format: {date_input}")
    else:
        raise TypeError(f"Expected str or datetime, got {type(date_input)}")

def randomise_date_with_interval(start_date, end_date, interval_range=10):
    """Randomise dates but preserve interval and avoiding future dates."""
    start_date_obj = parse_date_safe(start_date)
    end_date_obj = parse_date_safe(end_date)

    delta_days = (end_date_obj - start_date_obj).days

    # new start date, ensure it doesn't exceed today
    today = datetime.today()
    new_start_date = start_date_obj + timedelta(days=random.randint(-interval_range, interval_range))
    new_start_date = min(new_start_date, today)

    # new end date relative to new start date
    new_end_date = new_start_date + timedelta(days=delta_days)
    new_end_date = min(new_end_date, today)


    
    # DEBUG | TEMPORARY - Force both dates to day = 1 (so i can easily confirm in any outputs)
    new_start_date = new_start_date.replace(day=1)
    new_end_date = new_end_date.replace(day=1)


    
    return new_start_date.strftime("%Y-%m-%d"), new_end_date.strftime("%Y-%m-%d")


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



def extract_all_paths(data, prefix=""):
    """
    Recursively extract all possible dot-separated key paths from nested dicts/lists.
    """
    paths = set()
    if isinstance(data, dict):
        for key, value in data.items():
            full_key = f"{prefix}.{key}" if prefix else key
            paths.add(full_key)
            paths.update(extract_all_paths(value, full_key))
    elif isinstance(data, list):
        for item in data:
            paths.update(extract_all_paths(item, prefix))
    return paths



def audit_json_structure(records):
    print("\n🔍 Running JSON structure audit for nested fields...")

    misplaced_fields = ["uasc_flag", "uasc_end_date"]
    violations = []

    for i, record in enumerate(records):
        try:
            data = json.loads(record["json_payload"]) if isinstance(record["json_payload"], str) else record["json_payload"]
            child_details = data.get("child_details", {})

            for field in misplaced_fields:
                # Check if field exists at root level
                if field in data:
                    violations.append((i + 1, field, "❌ Found at root level"))
                # Check if it's missing entirely
                elif field not in child_details:
                    violations.append((i + 1, field, "⚠️ Missing from child_details"))

        except Exception as e:
            violations.append((i + 1, "⚠️ Error", str(e)))

    if violations:
        print("\n⚠️ Structural Issues Detected:\n")
        for rec in violations:
            print(f"Record {rec[0]:>3} | Field: {rec[1]:<20} | Issue: {rec[2]}")
    else:
        print("✅ All records have expected nested fields in the correct place.\n")


import json
from collections.abc import Mapping

def merge_structures(base, new):
    """
    Recursively merge keys from `new` into `base`, keeping default placeholder values.
    """
    for key, value in new.items():
        if key not in base:
            base[key] = normalise_value(value)
        elif isinstance(value, Mapping) and isinstance(base[key], Mapping):
            merge_structures(base[key], value)
        elif isinstance(value, list) and isinstance(base[key], list) and value and isinstance(value[0], Mapping):
            # Handle lists of dicts (e.g., sdq_assessments)
            if not base[key]:
                base[key].append({})
            merge_structures(base[key][0], value[0])
    return base

def normalise_value(value):
    """
    Generate a placeholder based on json value's type.
    """
    if isinstance(value, str):
        return ""
    elif isinstance(value, bool):
        return False
    elif isinstance(value, int):
        return 0
    elif isinstance(value, float):
        return 0.0
    elif isinstance(value, list):
        return [""] if value and isinstance(value[0], str) else []
    elif isinstance(value, dict):
        return merge_structures({}, value)
    return ""





## Pull the raw identifiable data from the source db table

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
        # la_child_id_list = ["129221", "102228", "102191"]
        # sql_query = f"SELECT * FROM ssd_api_data_staging WHERE person_id IN ({', '.join(f"'{id}'" for id in la_child_id_list)})"
        sql_query = f"SELECT * FROM ssd_api_data_staging"

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
    rows = cursor.fetchall() # db raw data records ready for processing
    column_names = [desc[0] for desc in cursor.description]  # Get col names

    # Calc fetch time
    fetch_time = time.time() - fetch_start_time
    print(f"Fetched {len(rows)} records from raw source ssd_api_data_staging in {fetch_time:.2f} seconds using query: {sql_query}")

except pyodbc.Error as e:
    print(f"Error fetching records: {e}")
    raise

## END Pull the raw identifiable data from the source db table




processed_data = []
anonymised_attributes = set() # track anonymised attributes, make it explicit on run which fields have been anonymised! 
all_original_keys = set() # Extract all keys BEFORE anonymisation

# process timer
processing_start_time = time.time()








## process records/raw identifiable data in memory

# json structure check(s)
audit_json_structure(rows)


# ✅ Store original and anonymised records for comparison
original_records = []
anonymised_records = []
schema_structure = {}


# ✅ Process records in memory
for i, row in enumerate(rows):

    record = dict(zip(column_names, row))  # Convert row to dictionary - incoming data as : (0, "123", '{"la_child_id":"1","child_details":{...}}')
    record_id = record["id"]
    person_id = record["person_id"]
    json_payload = json.loads(record["json_payload"])

    json_payload = normalise_keys(json_payload)  # Normalise keys

    
    ## Construct from available data/record unified schema with placeholder values
    # ✅ Call schema builder (on dict)
    merge_structures(schema_structure, json_payload)

    # ✅ schema_structure grows over iterations(not all records have complete struct)
    # ✅ Only print schema at last record
    if i == len(rows) - 1:
        # ✅ Add fixed top-level keys after final merge
        schema_structure["la_child_id"] = ""
        schema_structure["mis_child_id"] = ""
        
        # ✅ Wrap the final schema in a list
        final_schema_array = [schema_structure]
        
        # ✅ Output once, at the end
        print(json.dumps(final_schema_array, indent=2))

    ## END sample structure building
    

    
    # ✅ Store the original record for later comparison
    original_records.append(json.dumps(json_payload, indent=2))  # Keep JSON structure for readability


    try:
        # --- ✅ Anonymisation Process ---

        # --- ✅ Child details block ---    
        child_details = json_payload.get("child_details", {})
    
        # --- ✅ Replace First Name and Surname ---
        child_details["first_name"] = "SSH_PH"
        child_details["surname"] = "SSD_PH"
        # RE-implement later. For now using SSH_PH to increase visibility on anon-record processing
        # json_payload["child_details"]["surname"] = faker.last_name()
        # json_payload["child_details"]["first_name"] = faker.first_name()
        
        anonymised_attributes.update(["child_details.first_name", "child_details.surname"])
    
        # --- ✅ Anonymise Top-Level Fields ---
        json_payload["la_child_id"] = hash_id(json_payload.get("la_child_id", ""), max_length=36)
        anonymised_attributes.add("la_child_id")
    
        json_payload["mis_child_id"] = hash_id(json_payload.get("mis_child_id", ""), max_length=36)
        anonymised_attributes.add("mis_child_id")
    
        # --- ✅ Anonymise child_details Fields ---
        dob = child_details.get("date_of_birth")
        anon_dob = normalise_dob(dob)
        child_details["date_of_birth"] = anon_dob
        anonymised_attributes.add("child_details.date_of_birth")
    
        child_details["expected_date_of_birth"] = random_date_after(datetime.today(), min_years=0, max_years=1)
        anonymised_attributes.add("child_details.expected_date_of_birth")
    
        child_details["sex"] = random_sex()
        child_details["ethnicity"] = random_ethnicity()
        child_details["postcode"] = random_postcode()
        anonymised_attributes.update(["child_details.sex", "child_details.ethnicity", "child_details.postcode"])
    
        # --- ✅ Anonymise Disabilities ---
        num_disabilities = random.randint(0, 5)
        child_details["disabilities"] = random.sample(
            ["NONE", "MOB", "HAND", "PC", "INC", "COMM", "LD", "HEAR", "VIS", "BEH", "CON", "AUT", "DDA"],
            num_disabilities
        )
        anonymised_attributes.add("child_details.disabilities")
    
        # --- ✅ Anonymise UASC Flags ---
        child_details["uasc_flag"] = random.choice([True, False])
        child_details["uasc_end_date"] = random_date_after(datetime.today(), min_years=0, max_years=1)
        anonymised_attributes.update(["child_details.uasc_flag", "child_details.uasc_end_date"])
    
        # --- ✅ Anonymise Unique Pupil Numbers ---
        if "unique_pupil_number" in child_details:
            child_details["unique_pupil_number"] = hash_id(child_details["unique_pupil_number"], max_length=13)
            anonymised_attributes.add("child_details.unique_pupil_number")
    
        if "former_unique_pupil_number" in child_details:
            child_details["former_unique_pupil_number"] = hash_id(child_details["former_unique_pupil_number"], max_length=13)
            anonymised_attributes.add("child_details.former_unique_pupil_number")
    
        # ✅ Replace child_details in case you reassign it
        json_payload["child_details"] = child_details


        

        # --- ✅ Anonymise Health & Wellbeing (Inside Social Care Episodes) ---
        for wellbeing in json_payload.get("health_and_wellbeing", {}).get("sdq_assessments", []):      
            if "date" in wellbeing: #
                wellbeing["date"] = random_date_after(anon_dob, min_years=4, max_years=16)
                anonymised_attributes.add("health_and_wellbeing.sdq_assessments.sdq_date")

            if "score" in wellbeing: #
                # where: Normal| Borderline| Cause for concern - 0-13 |14-16 |17-40 
                wellbeing["score"] = random.randint(1, 40)
                anonymised_attributes.add("health_and_wellbeing.sdq_assessments.sdq_score")

    
        
        # --- ✅ Anonymise Education, Health & Care Plans ---
        for ehc_plan in json_payload.get("education_health_care_plans", []):
            if "education_health_care_plan_id" in ehc_plan:
                ehc_plan["education_health_care_plan_id"] = hash_id(ehc_plan["education_health_care_plan_id"], max_length=36)
                anonymised_attributes.add("education_health_care_plans.education_health_care_plan_id")

            for date_field in ["request_received_date", "request_outcome_date", "assessment_outcome_date", "plan_start_date"]:
                if date_field in ehc_plan:
                    ehc_plan[date_field] = random_date_after(anon_dob, min_years=3, max_years=18)  # Date within childhood
                    anonymised_attributes.add(f"education_health_care_plans.{date_field}")


        
        # --- ✅ Anonymise Social Care Episodes ---
        episodes = json_payload.get("social_care_episodes")
        
        if isinstance(episodes, list):
            print(f"✅ Record {record_id}: 'social_care_episodes' contains list with {len(episodes)} episodes.")
            
            for episode in episodes:
                if "social_care_episode_id" in episode:
                    episode["social_care_episode_id"] = hash_id(episode["social_care_episode_id"], max_length=36)
                    anonymised_attributes.add("social_care_episodes.social_care_episode_id")
    

                referral_date = episode.get("referral_date")
                closure_date = episode.get("closure_date")
    
                if referral_date and closure_date:
                    episode["referral_date"], episode["closure_date"] = randomise_date_with_interval(referral_date, closure_date)
                    anonymised_attributes.update(["social_care_episodes.referral_date", "social_care_episodes.closure_date"])
                elif referral_date:
                    episode["referral_date"] = randomise_date_with_interval(referral_date, referral_date)[0]
                    anonymised_attributes.add("social_care_episodes.referral_date")
    
                episode["referral_source"] = random.choice(["1A", "1B", "2A", "2B", "3A", "3B"])
                episode["closure_reason"] = random.choice(["RC1", "RC2", "RC3", "RC4", "RC5"])
                episode["referral_no_further_action_flag"] = random.choice([True, False])  
                anonymised_attributes.update(["social_care_episodes.referral_source", "social_care_episodes.closure_reason", "social_care_episodes.referral_no_further_action_flag"])
    
    
                # --- ✅ Anonymise Care Worker Details (Must be inside social_care_episodes) ---
                for worker in episode.get("social_worker_details", []):  # instead of care_worker_details
                    if "worker_id" in worker:
                        worker["worker_id"] = hash_id(worker["worker_id"], max_length=12)  # Note hash length is field specific
                        anonymised_attributes.add("social_care_episodes.social_worker_details.worker_id")
                
                    start_date = worker.get("start_date")
                    end_date = worker.get("end_date")
                
                    if start_date and end_date:
                        worker["start_date"], worker["end_date"] = randomise_date_with_interval(start_date, end_date)
                        anonymised_attributes.update(["social_care_episodes.social_worker_details.start_date", "social_care_episodes.social_worker_details.end_date"])
                    elif start_date:
                        worker["start_date"] = randomise_date_with_interval(start_date, start_date)[0]
                        anonymised_attributes.add("social_care_episodes.social_worker_details.start_date")
                    elif end_date:
                        worker["end_date"] = randomise_date_with_interval(end_date, end_date)[0]
                        anonymised_attributes.add("social_care_episodes.social_worker_details.end_date")
    
            
                
                # --- ✅ Anonymise Child and Family Assessments ---
                for assessment in episode.get("child_and_family_assessments", []):
                    if "child_and_family_assessment_id" in assessment:
                        assessment["child_and_family_assessment_id"] = hash_id(assessment["child_and_family_assessment_id"], max_length=36)
                        anonymised_attributes.add("child_and_family_assessments.child_and_family_assessment_id")
        
                    start_date = assessment.get("start_date")
                    authorisation_date = assessment.get("authorisation_date")
        
                    if start_date and authorisation_date:
                        assessment["start_date"], assessment["authorisation_date"] = randomise_date_with_interval(start_date, authorisation_date)
                        anonymised_attributes.update(["child_and_family_assessments.start_date", "child_and_family_assessments.authorisation_date"])
                    elif start_date:
                        assessment["start_date"] = randomise_date_with_interval(start_date, start_date)[0]
                        anonymised_attributes.add("child_and_family_assessments.start_date")
                    elif authorisation_date:
                        assessment["authorisation_date"] = randomise_date_with_interval(authorisation_date, authorisation_date)[0]
                        anonymised_attributes.add("child_and_family_assessments.authorisation_date")
        
                    # ✅ Fixed: Added missing `factors` anonymisation / Max length 3
                    assessment["factors"] = random.sample(
                        [
                            "1A", "1B", "1C", "2A", "2B", "2C", "3A", "3B", "3C", "4A", "4B", "4C",
                            "5A", "5B", "5C", "6A", "6B", "6C", "7A", "8B", "8C", "8D", "8E", "8F",
                            "9A", "10A", "11A", "12A", "13A", "14A", "15A", "16A", "17A", "18B",
                            "18C", "19B", "19C", "20", "21", "22A", "23A", "24A"
                        ],
                        random.randint(1, 5)  
                    )
                    anonymised_attributes.add("child_and_family_assessments.factors")
        
        
                
                # Anonymise child_in_need_plans
                for plan in episode.get("child_in_need_plans", []):
                    
                    if "child_in_need_plan_id" in plan:
                        plan["child_in_need_plan_id"] = hash_id(plan["child_in_need_plan_id"], max_length=36)
                        anonymised_attributes.add("child_in_need_plans.child_in_need_plan_id")
        
                    start_date = plan.get("start_date", "").split("T")[0]
                    end_date = plan.get("end_date", "").split("T")[0]
        
                    if start_date and end_date:
                        plan["start_date"], plan["end_date"] = randomise_date_with_interval(start_date, end_date)
                        anonymised_attributes.add("child_in_need_plans.start_date")
                        anonymised_attributes.add("child_in_need_plans.end_date")
        
        
        
                # --- ✅ Anonymise Section 47 Assessments ---
                for assessment in episode.get("section_47_assessments", []):
                    if "section_47_assessment_id" in assessment:
                        assessment["section_47_assessment_id"] = hash_id(assessment["section_47_assessment_id"], max_length=36)
                        anonymised_attributes.add("section_47_assessments.section_47_assessment_id")
        
                    start_date = assessment.get("start_date")
                    icpc_date = assessment.get("icpc_date")
                    end_date = assessment.get("end_date")
        
                    # ✅ Anonymise start_date, icpc_date, and end_date if they exist
                    if start_date and end_date:
                        assessment["start_date"], assessment["end_date"] = randomise_date_with_interval(start_date, end_date)
                        anonymised_attributes.update(["section_47_assessments.start_date", "section_47_assessments.end_date"])
                    elif start_date:
                        assessment["start_date"] = randomise_date_with_interval(start_date, start_date)[0]
                        anonymised_attributes.add("section_47_assessments.start_date")
                    elif end_date:
                        assessment["end_date"] = randomise_date_with_interval(end_date, end_date)[0]
                        anonymised_attributes.add("section_47_assessments.end_date")
        
                    if icpc_date:
                        assessment["icpc_date"] = randomise_date_with_interval(icpc_date, icpc_date)[0]
                        anonymised_attributes.add("section_47_assessments.icpc_date")
        
                    # ✅ Anonymise icpc_required_flag (randomly set to True or False)
                    assessment["icpc_required_flag"] = random.choice([True, False])
                    anonymised_attributes.add("section_47_assessments.icpc_required_flag")
        
        
        
                # --- ✅ Anonymise Child Protection Plans ---
                for plan in episode.get("child_protection_plans", []):
                    if "child_protection_plan_id" in plan:
                        plan["child_protection_plan_id"] = hash_id(plan["child_protection_plan_id"], max_length=36)
                        anonymised_attributes.add("child_protection_plans.child_protection_plan_id")
        
                    start_date = plan.get("start_date")
                    end_date = plan.get("end_date")
        
                    # ✅ Anonymise start_date and end_date if they exist
                    if start_date and end_date:
                        plan["start_date"], plan["end_date"] = randomise_date_with_interval(start_date, end_date)
                        anonymised_attributes.update(["child_protection_plans.start_date", "child_protection_plans.end_date"])
                    elif start_date:
                        plan["start_date"] = randomise_date_with_interval(start_date, start_date)[0]
                        anonymised_attributes.add("child_protection_plans.start_date")
                    elif end_date:
                        plan["end_date"] = randomise_date_with_interval(end_date, end_date)[0]
                        anonymised_attributes.add("child_protection_plans.end_date")
        
        
                
        
                # --- ✅ Anonymise Child Looked After Placements ---
                for placement in episode.get("child_looked_after_placements", []):
                    if "child_looked_after_placement_id" in placement:
                        placement["child_looked_after_placement_id"] = hash_id(placement["child_looked_after_placement_id"], max_length=36)
                        anonymised_attributes.add("child_looked_after_placements.child_looked_after_placement_id")
        
                    start_date = placement.get("start_date")
                    end_date = placement.get("end_date")
        
                    # ✅ Randomise start and end dates while maintaining intervals
                    if start_date and end_date:
                        placement["start_date"], placement["end_date"] = randomise_date_with_interval(start_date, end_date)
                        anonymised_attributes.update(["child_looked_after_placements.start_date", "child_looked_after_placements.end_date"])
                    elif start_date:
                        placement["start_date"] = randomise_date_with_interval(start_date, start_date)[0]
                        anonymised_attributes.add("child_looked_after_placements.start_date")
                    elif end_date:
                        placement["end_date"] = randomise_date_with_interval(end_date, end_date)[0]
                        anonymised_attributes.add("child_looked_after_placements.end_date")
        
                    # ✅ Replace categorical fields with valid random codes
                    placement["start_reason"] = random.choice(["S", "M", "P", "C"]) 
                    placement["placement_type"] = random.choice(["K1", "K2", "R1", "R2"])
                    placement["end_reason"] = random.choice(["E1", "E2", "E3", "E4"])
                    placement["change_reason"] = random.choice(["CHILD", "CARER", "ORG", "OTHER"])
                    placement["postcode"] = random_postcode()  # Random / generated postcode

                    # add to tracking
                    anonymised_attributes.update([
                        "child_looked_after_placements.start_reason",
                        "child_looked_after_placements.placement_type",
                        "child_looked_after_placements.end_reason",
                        "child_looked_after_placements.change_reason",
                        "child_looked_after_placements.postcode"
                    ])

        ## turning this off to avoid verbose output. Otherwise hits for each record with no epiodes logged
        # else:
        #     print(f"⚠️ Record {record_id}: 'social_care_episodes' is missing or not a list (got {type(episodes)}) — skipping.")


        
        # --- ✅ Anonymise Adoption Details ---
        if "adoption" in episode:
            adoption = episode["adoption"]

            for date_field in ["initial_decision_date", "matched_date", "placed_date"]:
                if date_field in adoption:
                    adoption[date_field] = random_date_after(anon_dob, min_years=1, max_years=18)
                    anonymised_attributes.add(f"adoption.{date_field}")


        
        # --- ✅ Anonymise Care Leavers (At Root Level) ---
        if "care_leavers" in json_payload:
            care_leaver = json_payload["care_leavers"]
        
            if "contact_date" in care_leaver:
                care_leaver["contact_date"] = random_date_after(anon_dob, min_years=14, max_years=30)  
                anonymised_attributes.add("care_leavers.contact_date")
        
            if "activity" in care_leaver:
                care_leaver["activity"] = random.choice(["F1", "P1", "F2", "P2", "F4", "P4", "F5", "P5", "G4", "G5", "G6"])
                anonymised_attributes.add("care_leavers.activity")
        
            if "accommodation" in care_leaver:
                care_leaver["accommodation"] = random.choice(["B", "C", "D", "E", "G", "H", "K", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"])
                anonymised_attributes.add("care_leavers.accommodation")



    
    except Exception as e:
        print(f"⚠️ ERROR: Failed to process record {record_id} - {e}")
        # json_payload = {"error": f"❌ ERROR Processing Record {record_id}"}  # ✅ Ensure something is stored


    # ✅ Ensure anonymised record is ALWAYS added
    anonymised_records.append(json.dumps(json_payload, indent=2))


    if isinstance(record, dict):
        record["person_id"] = hash_id(person_id) if person_id else None
        record["json_payload"] = json.dumps(json_payload)
        processed_data.append(tuple(record.values()))
    else:
        print(f"⚠️ Skipping record {record_id} - expected dict, got {type(record)}: {record}")



    
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
