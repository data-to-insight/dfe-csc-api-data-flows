# API Configuration

Use this page as the single source of truth for configuration, regardless of whether running **PowerShell** or **Python** implementations.

---

## Required Values (DfE / Environment)

You will receive, or have access to the following from [DfE](https://pp-find-and-use-an-api.education.gov.uk/api/83):

- `TOKEN_ENDPOINT`
- `API_ENDPOINT`
- `CLIENT_ID`
- `CLIENT_SECRET`
- `SCOPE`
- `SUPPLIER_KEY` *(if applicable)*

You must also define a database connection to your reporting instance or SSD clone:

- `DB_CONNECTION_STRING` (for Python), or `Server`/`Database` values (for PowerShell).

---

## Python Runtime – `.env`

Copy the template `.env.example` to `.env` and populate:

```ini
DB_CONNECTION_STRING=Driver={ODBC Driver 17 for SQL Server};Server=SERVER\INSTANCE;Database=HDM_Local;Trusted_Connection=yes;
TOKEN_ENDPOINT=...
API_ENDPOINT=...
CLIENT_ID=...
CLIENT_SECRET=...
SCOPE=...
SUPPLIER_KEY=...
DEBUG=true
```

> Keep `.env` **outside source control**. Use OS file permissions to restrict access if needed.

---

## PowerShell Runtime – Variables

If using the PowerShell script, set the following variables at the top of the script or via parameters:

```powershell
$testingMode = $true              # true => NO data leaves the LA
$server      = "ESLLREPORTS00X"   # SQL Server/instance and location of $database 
$database    = "HDM_Local"        # SSD reporting DB / Example shown is for SystemC

# API (from DfE)
$tokenEndpoint = "..."            # OAuth token URL
$apiEndpoint   = "..."            # API base/submit URL
$clientId      = "..."            
$clientSecret  = "..."            
$scope         = "..."            
$supplierKey   = "..."            # If required
```

> Exact variable names may differ slightly by script version; the values are the same.

---

## Table/Schema Expectations

Your SSD deployment should include the **api_data_staging** table that the API pipeline reads and updates. The SQL to deploy and populate this table is within the release files bundle:

- `ssd_api_data_staging` (live)  
- `ssd_api_data_staging_anon` (safe development/testing copy)

Key fields within the staging table:
- `json_payload`, `previous_json_payload`, `partial_json_payload`
- `current_hash`, `previous_hash`
- `row_state` (e.g. `new`, `updated`, `deleted`, `unchanged`)
- `submission_status` (e.g. `pending`, `sent`, `error`, `testing`)
- `api_response`
- `submission_timestamp`

> These fields should be populated and are accessed during the API process, submission_status, api_response and submission_timestamp are the last to be accessed|written to on batch process completion.

---

## Testing Mode vs Live Mode

- **Testing mode** (recommended first): data **does not** leave the LA. The pipeline simulates calls and uses separate _anon/test table.
- **Live mode**: the pipeline submits payload(s) to the DfE API. Only enable after Phase 1/2 tests complete successfully.

---

## Secrets Handling – Recommendations

- Use Windows Credential Manager / environment variables for secrets where possible
- Limit read access to `.env`/scripts to the service account that will run scheduled tasks
- Rotate `CLIENT_SECRET` and any access tokens per your local security policy
