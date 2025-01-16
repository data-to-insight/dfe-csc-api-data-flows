import json
import pyodbc


# sudo apt-get update
# sudo apt-get install -y unixodbc-dev odbcinst
# sudo apt-get install -y msodbcsql17  # Or msodbcsql18 for latest version



# SQL Server connection details
CONN_DETAILS = {
    "driver": "{SQL Server}",
    "server": "ESLLREPORTS04V",
    "database": "HDM_Local",
    "trusted_connection": "yes"
}

# SQL query file
SQL_QUERY_FILE = "json_extract_ssd_base_plus_v3.sql"
# Output sample data file
OUTPUT_FILE = "json_extract_ssd_base_plus_v3.json"

# Number of rows to extract
NUM_ROWS = 10

def anonymise_data(row):
    """Anonymise a row of data."""
    anonymised_row = {}
    for key, value in row.items():
        if isinstance(value, str):
            anonymised_row[key] = ""  # Nullify strings
        elif isinstance(value, (int, float)) and "id" in key.lower():
            anonymised_row[key] = 12345  # Replace IDs
        elif isinstance(value, (int, float)):
            anonymised_row[key] = 0  # Default for numeric values
        elif isinstance(value, list):
            anonymised_row[key] = ["A", "B", "C"]  # Generic list
        elif isinstance(value, (dict, tuple)):
            anonymised_row[key] = anonymise_data(value)  # Recursive anonymisation
        elif "date" in key.lower() and value is not None:
            anonymised_row[key] = "1900-01-01"  # Default date
        else:
            anonymised_row[key] = None  # Default for other types
    return anonymised_row

def main():
    # Read SQL query
    with open(SQL_QUERY_FILE, "r") as f:
        sql_query = f.read()

    # Connect to SQL Server
    conn_str = (
        f"DRIVER={CONN_DETAILS['driver']};"
        f"SERVER={CONN_DETAILS['server']};"
        f"DATABASE={CONN_DETAILS['database']};"
        f"Trusted_Connection={CONN_DETAILS['trusted_connection']}"
    )
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()

    # Execute the query with a row limit
    query_with_limit = f"SELECT TOP {NUM_ROWS} * FROM ({sql_query}) AS subquery"
    cursor.execute(query_with_limit)

    # Fetch results
    columns = [column[0] for column in cursor.description]
    rows = [dict(zip(columns, row)) for row in cursor.fetchall()]

    # Anon results
    anonymised_data = [anonymise_data(row) for row in rows]

    # Write results to JSON
    with open(OUTPUT_FILE, "w") as f:
        json.dump(anonymised_data, f, indent=4)

    print(f"Anonymised data has been written to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
