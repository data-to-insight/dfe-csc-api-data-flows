import json
import re

# Input SQL query file
SQL_QUERY_FILE = "json_extract_ssd_base_plus_v3.sql"
# Output sample data file
OUTPUT_FILE = "json_extract_ssd_base_plus_v3.json"
def parse_sql_query(sql_query):
    """Parse the SQL query to extract field names and nesting structure."""
    data_structure = {}

    # Regex patterns to match fields and nesting
    top_level_pattern = re.compile(r"^(\w+) AS \[(\w+(\.\w+)*)\]", re.MULTILINE)
    nested_block_pattern = re.compile(r"\(\s*SELECT\s+(.+?)\s+AS \[(\w+(\.\w+)*)\]", re.DOTALL)

    # Extract top-level fields
    for match in top_level_pattern.finditer(sql_query):
        field_name = match.group(2)
        if "." not in field_name:
            data_structure[field_name] = None

    # Extract nested blocks
    for match in nested_block_pattern.finditer(sql_query):
        nested_field = match.group(2)
        nested_parts = nested_field.split('.')
        current_level = data_structure

        for part in nested_parts[:-1]:
            if part not in current_level:
                current_level[part] = {}
            current_level = current_level[part]

        current_level[nested_parts[-1]] = [{}]  # Represent nested blocks as lists of dicts

    return data_structure

def generate_sample_data(structure):
    """Generate sample data based on the structure."""
    sample_data = {}

    for key, value in structure.items():
        if isinstance(value, list):
            sample_data[key] = [generate_sample_data(value[0] if value else {})]
        elif isinstance(value, dict):
            sample_data[key] = generate_sample_data(value)
        else:
            if "date" in key.lower():
                sample_data[key] = "1900-01-01"
            elif "id" in key.lower():
                sample_data[key] = "12345"
            elif key.lower() in ["first_name", "surname"]:
                sample_data[key] = "SSD_PH"
            elif key.lower() == "sex":
                sample_data[key] = "U"
            else:
                sample_data[key] = "null"

    return sample_data

def main():
    # Read the SQL query
    with open(SQL_QUERY_FILE, "r") as f:
        sql_query = f.read()

    # Parse the SQL query to extract structure
    structure = parse_sql_query(sql_query)

    # Generate sample data
    sample_data = generate_sample_data(structure)

    # Write sample data to a JSON file
    with open(OUTPUT_FILE, "w") as f:
        json.dump(sample_data, f, indent=4)

    print(f"Sample data has been written to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
