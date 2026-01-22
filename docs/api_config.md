# API Configuration

Use this page as the single source of truth for api sender configuration, regardless of whether running **PowerShell** or **Python** implementations. 

> Note: As the project remains in pilot/alpha stage(s), there may have been changes in released/current code that differs from or is not reflected in some parts of the documentation detail. Colleague observations and feedback welcomed towards improving this for everyone.

---

## Required Values (DfE / Environment)

You will receive, or have access to the following from the [DfE API Portal](https://pp-find-and-use-an-api.education.gov.uk/api/83):

- `API_ENDPOINT` 
- `SUPPLIER_KEY`  
- `TOKEN_ENDPOINT` 
- `CLIENT_ID` 
- `CLIENT_SECRET`  
- `SCOPE` 

You must also define a database connection to your reporting instance or SSD clone:

- `DB_CONNECTION_STRING` (for Python), or `Server`/`Database` values (for PowerShell)

---

## Python Runtime – `.env`

Either type/paste the DfE details for your LA into the api sender script directly or copy the template `.env.example` to `.env` and populate:

```ini
DB_CONNECTION_STRING=Driver={ODBC Driver 17 for SQL Server};Server=SERVER\INSTANCE;Database=HDM_Local;Trusted_Connection=yes;
API_ENDPOINT=...
SUPPLIER_KEY=...
TOKEN_ENDPOINT=...
CLIENT_ID=...
CLIENT_SECRET=...
SCOPE=...
```

> Keep your connection secrets, including `.env` **as non- public/wider access**. Use OS file permissions to restrict access if needed.

---

## PowerShell Runtime – Variables

If using the PowerShell script, set the following variables at the top of the script or via parameters:

```powershell
# API DfE Config (from DfE)
# 'Subscription key' block
$supplier_key    = "SUBSCRIPTION_PRIMARY_KEY_CODE"       # 'Primary key' or 'Secondary key'

# 'Native OAuth Application-flow' block
$token_endpoint  = "OAUTH_TOKEN_ENDPOINT"                # 'OAuth token endpoint'

$client_id       = "OAUTH_CLIENT_ID_CODE"                # 'OAuth Client ID'
$client_secret   = "NATIVE_OAUTH_PRIMARY_KEY_CODE"       # 'Primary key' or 'Secondary key'
$scope           = "OAUTH_SCOPE_LINK"                    # 'OAuth Scope'

```
and then also

```powershell
# API LA Config
$la_code     = "000"              # Your LA's 3 digit code
$server      = "ESLLREPORTS00X"   # SQL Server/instance and location of $database 
$database    = "HDM_Local"        # SSD reporting DB / Example shown is for SystemC

# and initially also check
$testingMode = $true              # true => NO data leaves the LA (set to $false when ready to send fake payload)

```

> Exact variable names may differ slightly by script version; the values are the same.

---

## Table/Schema Expectations

Your SSD deployment should include/be appended with the additional **api_data_staging** table. This table is read and updated by the API pipeline. The SQL to deploy and populate this table is within the [API/EA release files bundle](https://data-to-insight.github.io/dfe-csc-api-data-flows/release/):  

SSD non-core tables added to enable API project:
- `ssd_api_data_staging` (live)  
- `ssd_api_data_staging_anon` (safe development/testing copy) 

Key fields within the staging table:
- `json_payload`, `previous_json_payload`, `partial_json_payload`
- `current_hash`, `previous_hash`
- `row_state` (e.g. `new`, `updated`, `deleted`, `unchanged`)
- `submission_status` (e.g. `pending`, `sent`, `error`, `testing`)
- `api_response`
- `submission_timestamp`

> These already populated fields are accessed during the API process by the api sender; and submission_status, api_response and submission_timestamp are the last to be accessed|re-written on batch process completion by the api sender tool.  

---

## Testing Mode vs Live Mode

- **Testing mode** (recommended first): data **does not** leave the LA. The pipeline simulates calls and uses separate _anon/test table.
- **Live mode**: the pipeline submits fake|live payload(s) to the DfE API. Only enable after Phase 1/2 tests complete successfully.

---

## Secrets Handling – Recommendations

- Use Windows Credential Manager / environment variables for secrets where possible
- Limit read access to `.env`/scripts to the service account that will run scheduled tasks
- Rotate `$supplier_key` and `$client_secret` and any access tokens per your local security policy
- You can also request a credentials reset/refresh from the DfE if needed
