# CSC API Sender Script - User Guide

_script : api_payload_sender.ps1 (v0.4.2)_

This guide attempts to explain what the script does, how to run it safely, and how to choose options for test and live-like runs. Written for colleagues|pilot teams.
---

## Quick script overview

- Reads prebuilt JSON payloads from SQL Server table `ssd_api_data_staging_anon` by default
- Sends records to DfE CSC API endpoint batched as per DfE spec
- Supports full payload mode and deltas mode(this in progress)
- Record server response back to staging table for auditing etc
- Provide hard coded test record option that avoids any database read
- Offers a dry run mode that skips any network calls
- Can run with LA HTTP proxy
- Handles Windows authentication to SQL or SQL Login authentication
- Output brief performance and diagnostics summary

---

## Safety features

- Default table points at `ssd_api_data_staging_anon` which must contain only safe fake data
- Dry run mode available using `-InternalTest`
- Hard coded test record available using `-UseTestRecord`
- Batches and timeouts are controlled to reduce accidental load
- HTTP diagnostics printed on error, including non HTTP failures such as DNS and TLS
- Copy paste diagnostics section to share with d2i

---

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7
- Network route to API endpoint
- TLS 1.2 enabled on host
- SQL Server connectivity to SSD schema/db
- If using SQL authentication, `DB_USER` and `DB_PASSWORD` environment variables or pass `-DbUser` and `-DbPassword`

---

## Key parameters and defaults

Unless you pass a parameter on command line, script uses safer defaults. The script also sets default values programmatically when parameter is not supplied.

- `-Phase`  
  `full` or `deltas`  
  Default `full`

- `-BatchSize`  
  Max records per POST  
  Default `100`

- `-ApiTimeout`  
  Per request timeout in seconds  
  Default `30`

- `-UseTestRecord`  
  Uses built in fake|hard coded payload and skips db read  
  Default off

- `-InternalTest`  
  Simulates send and does not call API  
  Default off

- `-UseIntegratedSecurityDbConnection`  
  Windows authentication to SQL when present. If not passed, the script enables this by default  
  Default on

- `-DbUser`, `-DbPassword`  
  Only used when `-UseIntegratedSecurityDbConnection:$false`

- `-Proxy`, `-ProxyUseDefaultCredentials`, `-ProxyCredential`  
  Optional HTTP proxy. If you supply credentials you must also supply proxy URI

The script applies proxy defaults to all `Invoke-WebRequest` and `Invoke-RestMethod` calls using `$PSDefaultParameterValues`. If you do not pass proxy settings then no proxy is used.

---

## Data sources and tables

- Default table is `ssd_api_data_staging_anon`
- Production table is `ssd_api_data_staging`
- Switch between them by changing the variable in script configuration section

Only `ssd_api_data_staging_anon` should be used during client testing until sign off. It must contain no live data.

---

## Modes of operation

### Full payload mode
Sends payload from `json_payload` column

### Deltas mode
Generate and sends minimal changes based on `partial_json_payload` and previous payload state

### Hard coded test record
Send a single safe record created in script function `Get-HardcodedTestRecord`

### Dry run
Skips all outbound web calls. Useful to check database reads and batching logic

---

## Typical run scenarios

### 1) Default run with Windows auth to SQL and no proxy
Reads from `ssd_api_data_staging_anon`, sends full(non-delta) payloads, batch size 100
```powershell
.\api_payload_sender.ps1
```

### 2) Explicit Windows auth to SQL and full mode
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\api_payload_sender.ps1 `
  -Phase full `
  -BatchSize 100 `
  -ApiTimeout 30 `
  -UseIntegratedSecurityDbConnection `
  -ProxyUseDefaultCredentials:$false
```

### 3) Deltas mode from _anon table
```powershell
.\api_payload_sender.ps1 -Phase deltas
```

### 4) Hard-coded fake test record sent to API
No database read(s). Useful for connectivity checks
```powershell
.\api_payload_sender.ps1 -UseTestRecord
```

### 5) Dry run with real DB records
No API calls made
```powershell
.\api_payload_sender.ps1 -InternalTest
```

### 6) SQL authentication to DB
Provide credentials or rely on environment variables
```powershell
# using explicit parameters
.\api_payload_sender.ps1 -UseIntegratedSecurityDbConnection:$false -DbUser my_user -DbPassword 'P@ssw0rd!'

# or using environment variables set beforehand
$env:DB_USER = 'my_user'
$env:DB_PASSWORD = 'P@ssw0rd!'
.\api_payload_sender.ps1 -UseIntegratedSecurityDbConnection:$false
```

### 7) Proxy with default user credentials
```powershell
.\api_payload_sender.ps1 -Proxy 'http://proxy.example.local:8080' -ProxyUseDefaultCredentials
```

### 8) Proxy with explicit credentials
```powershell
$cred = Get-Credential   # supply proxy user and password
.\api_payload_sender.ps1 -Proxy 'http://proxy.example.local:8080' -ProxyCredential $cred
```

---

## How the script chooses defaults

The script uses `PSBoundParameters` to detect when parameter was passed. If parameter is omitted, helper logic sets safe default. E.g.s:

- If `UseIntegratedSecurityDbConnection` not passed, set to `$true`
- If `ProxyUseDefaultCredentials` not passed and `Proxy` is not given, proxy is not used
- If `ProxyCredential` supplied without `Proxy`, token calls would fail. script validates this and stops with message

---

## Database connection behaviour

The script builds the SQL connection string with `SqlConnectionStringBuilder`:

- Windows authentication: `Integrated Security=True`, `Encrypt=True`, `TrustServerCertificate=True`
- SQL authentication: `Integrated Security=False`, sets `User ID` and `Password`, `Encrypt=True`, `TrustServerCertificate=True` by default
- If you use a certificate signed by a trusted CA you can set `TrustServerCertificate=False` in the configuration section

If you see trust failures when using SQL authentication, either install the trusted root CA or temporarily use `TrustServerCertificate=True` as documented above.

---

## Proxy behaviour

When `-Proxy` given the script writes to `$PSDefaultParameterValues` so that all web requests use the same proxy. If you pass `-ProxyUseDefaultCredentials` it will use the account running the script. If you pass `-ProxyCredential` you must also pass `-Proxy`.

If you do not pass any proxy options there is no proxy involvement.

---

## Understanding the output

- Start and end banners show timestamps and version
- Endpoint line confirms which API URL was used
- Records count shows how many items will be sent
- For each batch the script prints the batch number
- On success the API returns a list of `yyyy-MM-dd_HH:mm:ss.ff_<uuid>.json` tokens which are then recorded in the database
- A performance summary shows total script time and cumulative database write time
- On errors a copy friendly diagnostics block appears

---

## Common errors and hints

- `oauth fail: invalid_client`  
  Check client id and secret and scope values

- `401` token errors during send  
  Token maybe expired. Script gets fresh token on start. Check clock skew on host

- `403` or `404` on send  
  Wrong API scope or endpoint. Confirm base URL and path contain the LA code

- `407 Proxy Authentication Required`  
  Supply `-Proxy` and either `-ProxyUseDefaultCredentials` or `-ProxyCredential`

- SQL login trust failure  
  Use `Encrypt=True` and either install trusted CA or set `TrustServerCertificate=True` as described

---

## Switching between anon and live tables

Change this line in configuration section
```powershell
$api_data_staging_table = "ssd_api_data_staging_anon"   # test table with fake data
# $api_data_staging_table = "ssd_api_data_staging"      # live table enabled only after sign off
```

Ensure governance sign off before switching to the live table.

---

## Versioning and change control

- Version ref shown at start, e.g. `v0.4.2`
- Keep this guide alongside the script in source control
- Update the scenarios and defaults here when you change script behaviour

---

## Contact and support

- Pls include copy block from the end of script when raising issues
- Provide exact command line used and any proxy or DB mode used
