<#
.SYNOPSIS
  SSD -> CSC API batch sender (full or deltas) with optional proxy and DB auth modes

.DESCRIPTION
  Pulls pending JSON payloads from SQL Server ($api_data_staging_table), batches and POSTs to CSC endpoint
  Supports full or deltas payloads, retry with exponential backoff, and optional hard-coded test record
  Proxy can be passed with -Proxy or taken from $la_proxy when not supplied, and is applied to token and POST
  .NET DefaultWebProxy is aligned so underlying HTTP clients follow same proxy and credential rules
  DB auth can be Windows Integrated or SQL auth

.PARAMETER Phase
  Payload mode: 'full' or 'deltas'. 'deltas' prepares and uses partial_json_payload before sending

.PARAMETER InternalTest
  Dry run; skip real POST

.PARAMETER UseTestRecord
  Sends single hard-coded fake record for connectivity tests and skips DB update

.PARAMETER BatchSize
  Max records per POST (DfE default is 100)

.PARAMETER ApiTimeout
  Per request HTTP timeout in seconds

.PARAMETER Proxy
  Proxy URI, e.g. http://proxy.myLA.local:8080
  If omitted and $la_proxy is set, that value used

.PARAMETER ProxyUseDefaultCredentials
  Use current Windows logon for proxy auth when using -Proxy or $la_proxy

.PARAMETER ProxyCredential
  PSCredential for proxy auth. Ignored if -ProxyUseDefaultCredentials is present

.PARAMETER UseIntegratedSecurityDbConnection
  Use Windows Integrated Security for SQL. When not used, SQL auth is taken from -DbUser/-DbPassword
  or DB_USER/DB_PASSWORD environment variables

.PARAMETER DbUser
  SQL login used when not using Windows Integrated Security

.PARAMETER DbPassword
  SQL password used when not using Windows Integrated Security

.NOTES
  Requires: PowerShell 5.1+
  TLS: script forces TLS 1.2
  Retries: up to 3 with exponential backoff (not retried: 204, 400, 413)
  Legacy mappings retained: $usePartialPayload, $internalTesting, $useTestRecord, $batchSize, $timeoutSec
  Proxy defaults: if -Proxy not provided and $la_proxy is set, that proxy is used; if no proxy creds flags are passed, defaults to current Windows logon

.EXAMPLE
  # Smallest: use built-in hard-coded record and POST to API
  powershell -NoProfile -File .\phase_1_api_payload.ps1 -UseTestRecord -Phase full -BatchSize 1

.EXAMPLE
  # With LA proxy using Windows creds
  powershell -NoProfile -File .\phase_1_api_payload.ps1 -UseTestRecord `
    -Proxy 'http://proxy.myLA.local:8080' -ProxyUseDefaultCredentials

.EXAMPLE
  # With explicit proxy creds
  powershell -NoProfile -File .\phase_1_api_payload.ps1 -UseTestRecord `
    -Proxy 'http://proxy.myLA.local:8080' -ProxyUseDefaultCredentials:$false `
    -ProxyCredential (Get-Credential)

.EXAMPLE
  # Full send, Windows auth to SQL (no proxy)
  powershell -NoProfile -ExecutionPolicy Bypass -File .\phase_1_api_payload.ps1 `
    -Phase full -UseIntegratedSecurityDbConnection

.EXAMPLE
  # Deltas, SQL auth to DB using env vars, with LA proxy and default creds
  $env:DB_USER = "svc_csc"; $env:DB_PASSWORD = "P@ssw0rd!"
  powershell -NoProfile -ExecutionPolicy Bypass -File .\phase_1_api_payload.ps1 `
    -Phase deltas -Proxy http://proxy.myLA.local:8080 -ProxyUseDefaultCredentials

.EXAMPLE
  # Full send with explicit proxy credential and custom timeout
  $pcred = Get-Credential
  powershell -NoProfile -ExecutionPolicy Bypass -File .\phase_1_api_payload.ps1 `
    -Phase full -Proxy http://proxy.myLA.local:8080 -ProxyCredential $pcred -ApiTimeout 45

.EXAMPLE
  # Dry run with hard-coded test record
  powershell -NoProfile -ExecutionPolicy Bypass -File .\phase_1_api_payload.ps1 `
    -Phase full -UseTestRecord -InternalTest

# Save as UTF-8 with BOM in VS Code if non ASCII symbols present
#>

[CmdletBinding()]
param(
  [ValidateSet('full','deltas')] [string]$Phase = 'full',  # payload type
  [switch]$InternalTest,                                   # simulate send
  [switch]$UseTestRecord,                                  # use hard-coded fake record
  [ValidateRange(1,100)] [int]$BatchSize = 100,            # DfE max batch size is 100
  [ValidateRange(5,60)]  [int]$ApiTimeout = 30,            # in secs
  [string]$Proxy,
  [switch]$ProxyUseDefaultCredentials,
  [PSCredential]$ProxyCredential,
  [string]$DbUser = $env:DB_USER,
  [string]$DbPassword = $env:DB_PASSWORD,
  [switch]$UseIntegratedSecurityDbConnection               # use Windows auth when present
)

$VERSION = '0.4.5'
Write-Host ("CSC API staging build: v{0}" -f $VERSION)





# ----------- LA DfE Config START -----------

# LA's to replace the following details(in quotes) with your LA's credentials as supplied by DfE API portal
# from https://pp-find-and-use-an-api.education.gov.uk/ (logged in)

# Base URL TEST
$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1" 

# Base URL PP/Live (switch over only when sending live records)
# $api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver/1"


# 'Subscription key' block
$supplier_key    = "SUBSCRIPTION_PRIMARY_KEY_CODE"       # 'Primary key' or 'Secondary key'

# 'Native OAuth Application-flow' block
$token_endpoint  = "OAUTH_TOKEN_ENDPOINT"                # 'OAuth token endpoint'

$client_id       = "OAUTH_CLIENT_ID_CODE"                # 'OAuth Client ID'
$client_secret   = "NATIVE_OAUTH_PRIMARY_KEY_CODE"       # 'Primary key' or 'Secondary key'
$scope           = "OAUTH_SCOPE_LINK"                    # 'OAuth Scope'

# -- DfE Config END --

# LA specifics
$la_code  = "000"     # Change to your 3 digit LA code(within quotes)

# LA SQL Server target
$server   = "ESLLREPORTS04V" # example
$database = "HDM_Local" # SystemC default

# Only some LAs will need to set this
$la_proxy = $null     # LA default proxy ($null or '' disables, or use such as "http://proxy.myLA.local:8080")

# payload table (_anon is non-live default)
$api_data_staging_table = "ssd_api_data_staging_anon"  # live: ssd_api_data_staging | test: _anon


# Optional local paths
$testOutputFilePath = "C:\Users\d2i\Documents\api_payload_test.json"
$logFile            = "C:\Users\d2i\Documents\api_temp_log.json"

# ----------- LA Config END -----------
















# ---- DEV OVERIDES (applied only when caller CLI/params not passed) ----------------
# defaults to make manual runs easier, these do not override CLI values 
if (-not $PSBoundParameters.ContainsKey('Phase'))                             { $Phase  = 'full' } # 'full' or 'deltas'
if (-not $PSBoundParameters.ContainsKey('InternalTest'))                      { $InternalTest = $false } # true=no external calls
if (-not $PSBoundParameters.ContainsKey('UseTestRecord'))                     { $UseTestRecord = $true } # false switches to payload data being pulled from db
if (-not $PSBoundParameters.ContainsKey('Proxy'))                             { $Proxy = $null } # e.g. 'http://proxy.myLA.local:8080' but $null==not forcing specific proxy URI/web cmdlets use OS/.NET system proxy(WinINET/WinHTTP/PAC) if one configured; otherwise go direct
if (-not $PSBoundParameters.ContainsKey('ProxyUseDefaultCredentials'))        { $ProxyUseDefaultCredentials = $false } # cmdlets will send current users Win creds to proxy when challenged
if (-not $PSBoundParameters.ContainsKey('ApiTimeout'))                        { $ApiTimeout = 20 } # seconds (HTTP tuning)
if (-not $PSBoundParameters.ContainsKey('BatchSize'))                         { $BatchSize  = 100 }
if (-not $PSBoundParameters.ContainsKey('UseIntegratedSecurityDbConnection')) { $UseIntegratedSecurityDbConnection = $true }

## Quick matrix for HTTP proxy flag above use as options varied:
## Proxy=$null, ProxyUseDefaultCredentials=$true --> System proxy + default creds (or direct if none)
## Proxy='http://proxy.myLA.local:8080', ProxyUseDefaultCredentials=$true --> That proxy + default creds
## Proxy='http://proxy.myLA.local:8080', ProxyUseDefaultCredentials=$false, ProxyCredential=...--> That proxy + supplied creds
## So: null + true = use whatever proxy machine already has, and auth with my Windows creds if needed


# If using SQL auth, pick up env vars where needed
if (-not $UseIntegratedSecurityDbConnection) {
  if (-not $PSBoundParameters.ContainsKey('DbUser')     -and [string]::IsNullOrWhiteSpace($DbUser))     { $DbUser     = $env:DB_USER }
  if (-not $PSBoundParameters.ContainsKey('DbPassword') -and [string]::IsNullOrWhiteSpace($DbPassword)) { $DbPassword = $env:DB_PASSWORD }
}
# ------------------------------------------------------------------------------


# ---- TLS for older hosts - Incl reduce extra HTTP friction on older stacks (PShell 5.1) ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::Expect100Continue = $false 
[System.Net.ServicePointManager]::DefaultConnectionLimit = 10



# ---- Decide final Proxy first (include $la_proxy fallback) ----
# If caller did not pass -Proxy, but LA has a default proxy, use it.
if (-not $PSBoundParameters.ContainsKey('Proxy') -or [string]::IsNullOrWhiteSpace($Proxy)) {
  if ($la_proxy) { $Proxy = $la_proxy }
}

# If using a proxy and no creds choice was made, use current Windows user for NTLM
if ($Proxy -and -not $PSBoundParameters.ContainsKey('ProxyUseDefaultCredentials') -and -not $PSBoundParameters.ContainsKey('ProxyCredential')) {
  $ProxyUseDefaultCredentials = $true
}

# ---- Apply proxy defaults to web cmdlets (now that $Proxy is final) ----
# implicitly pass -Proxy and either -ProxyUseDefaultCredentials or -ProxyCredential on every web request
# clear any inherited session defaults so we don't accidentally pass proxy creds without a proxy
$PSDefaultParameterValues.Remove('Invoke-WebRequest:Proxy')                        2>$null
$PSDefaultParameterValues.Remove('Invoke-RestMethod:Proxy')                        2>$null
$PSDefaultParameterValues.Remove('Invoke-WebRequest:ProxyUseDefaultCredentials')   2>$null
$PSDefaultParameterValues.Remove('Invoke-RestMethod:ProxyUseDefaultCredentials')   2>$null
$PSDefaultParameterValues.Remove('Invoke-WebRequest:ProxyCredential')              2>$null
$PSDefaultParameterValues.Remove('Invoke-RestMethod:ProxyCredential')              2>$null

if ($Proxy) {
  $PSDefaultParameterValues['Invoke-WebRequest:Proxy'] = $Proxy
  $PSDefaultParameterValues['Invoke-RestMethod:Proxy'] = $Proxy

  if ($ProxyUseDefaultCredentials) {
    $PSDefaultParameterValues['Invoke-WebRequest:ProxyUseDefaultCredentials'] = $true
    $PSDefaultParameterValues['Invoke-RestMethod:ProxyUseDefaultCredentials'] = $true
  } elseif ($ProxyCredential) {
    $PSDefaultParameterValues['Invoke-WebRequest:ProxyCredential'] = $ProxyCredential
    $PSDefaultParameterValues['Invoke-RestMethod:ProxyCredential'] = $ProxyCredential
  }
}

# ---- Align .NET DefaultWebProxy so any lower level HTTP follows the same rule ----
try {
  if ($Proxy) {
    $wp = New-Object System.Net.WebProxy($Proxy, $true)  # true = bypass local
    if ($ProxyUseDefaultCredentials) {
      $wp.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    } elseif ($ProxyCredential) {
      $wp.Credentials = $ProxyCredential.GetNetworkCredential()
    }
    [System.Net.WebRequest]::DefaultWebProxy = $wp
  } else {
    $def = [System.Net.WebRequest]::DefaultWebProxy
    if ($def -and -not $def.Credentials) {
      $def.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    }
  }
} catch { }

# ---- Dev convenience mapping to legacy var names ----
$usePartialPayload = ($Phase -eq 'deltas')   # full=false, deltas=true
$internalTesting   = [bool]$InternalTest
$useTestRecord     = [bool]$UseTestRecord
$batchSize         = $BatchSize
$timeoutSec        = $ApiTimeout







# ----------- Config OVERIDE ---------------
# D2I Overide block
# ----------- Config OVERIDE END -----------










# ---- Proxy auto-defaults + align .NET default proxy ---- 
# uses # $la_proxy optional set in config above

# Default proxy IF caller did not pass -Proxy (keeps friendly $la_proxy up top)
if (-not $PSBoundParameters.ContainsKey('Proxy') -or [string]::IsNullOrWhiteSpace($Proxy)) {
  if ($la_proxy) { $Proxy = $la_proxy } # Pass -Proxy at run time to override anything set in $la_proxy
}

# If LA using proxy and no creds choice was made, use current Windows user for NTLM
if ($Proxy -and -not $PSBoundParameters.ContainsKey('ProxyUseDefaultCredentials') -and -not $PSBoundParameters.ContainsKey('ProxyCredential')) {
  $ProxyUseDefaultCredentials = $true
}

# Align .NET's DefaultWebProxy so HTTP calls not passing -Proxy still use same settings
try {
  if ($Proxy) {
    # Use explicit proxy (or default above) for all .NET web requests also
    $wp = New-Object System.Net.WebProxy($Proxy, $true)  # $true = bypass local
    if ($ProxyUseDefaultCredentials) {
      $wp.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    } elseif ($ProxyCredential) {
      # IMPORTANT: convert PSCredential to NetworkCredential for WebProxy
      $wp.Credentials = $ProxyCredential.GetNetworkCredential()
    }
    [System.Net.WebRequest]::DefaultWebProxy = $wp
  } else {
    # No explicit proxy - keep machine-wide defaults but ensure NTLM with current user if creds empty
    $def = [System.Net.WebRequest]::DefaultWebProxy
    if ($def -and -not $def.Credentials) {
      $def.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    }
  }
} catch { }
# -----------------------------------------------------------------------------------------------


# log helpers
function W-Info($m){ Write-Host $m -ForegroundColor Gray }
function W-Ok($m){ Write-Host $m -ForegroundColor Green }
function W-Warn($m){ Write-Host $m -ForegroundColor Yellow }
function W-Err($m){ Write-Host $m -ForegroundColor Red }
function W-Dim($m){ Write-Host $m -ForegroundColor DarkGray }

$scriptStart = Get-Date
$scriptStartStamp = $scriptStart.ToString("yyyy-MM-dd HH:mm:ss")
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Started: $scriptStartStamp ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray

# timers
$swScript = [System.Diagnostics.Stopwatch]::StartNew()

# build endpoint
$api_endpoint_with_lacode = "$api_endpoint/children_social_care_data/$la_code/children"
W-Info "Final API Endpoint: $api_endpoint_with_lacode"

# Proxy helper used by token + POST calls (explicit pass-through even if defaults not set)
function Get-ProxySplat {
  $s = @{}
  if ($Proxy) { $s.Proxy = $Proxy }
  if ($ProxyUseDefaultCredentials) { $s.ProxyUseDefaultCredentials = $true }
  elseif ($ProxyCredential) { $s.ProxyCredential = $ProxyCredential }
  return $s
}


# helpers
function Test-Cfg {
  param($Api,$Token,$Id,$Sec,$Scope,$La,$Table,$Server,$Db)
  $missing = @()
  if([string]::IsNullOrWhiteSpace($Api)){ $missing += 'api_endpoint' }
  if([string]::IsNullOrWhiteSpace($Token)){ $missing += 'token_endpoint' }
  if([string]::IsNullOrWhiteSpace($Id)){ $missing += 'client_id' }
  if([string]::IsNullOrWhiteSpace($Sec)){ $missing += 'client_secret' }
  if([string]::IsNullOrWhiteSpace($Scope)){ $missing += 'scope' }
  if(-not $La){ $missing += 'la_code' }
  if([string]::IsNullOrWhiteSpace($Table)){ $missing += 'api_data_staging_table' }
  if([string]::IsNullOrWhiteSpace($Server)){ $missing += 'server' }
  if([string]::IsNullOrWhiteSpace($Db)){ $missing += 'database' }
  if($missing.Count){ W-Err ("cfg missing: {0}" -f ($missing -join ', ')); return $false }
  $true
}

function New-ApiHeaders {
  param($Token,$SupplierKey)
  @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $Token"
    "SupplierKey"   = $SupplierKey
  }
}

function Get-OAuthToken {
  $body = @{
    client_id     = $client_id
    client_secret = $client_secret
    scope         = $scope
    grant_type    = "client_credentials"
  }
  $proxy = Get-ProxySplat
  try {
    $resp = Invoke-RestMethod -Uri $token_endpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -TimeoutSec $timeoutSec -ErrorAction Stop @proxy
    return $resp.access_token
  } catch {
    W-Err ("oauth fail: {0}" -f $_.Exception.Message)
    return $null
  }
}

function Execute-NonQuerySql {
  param (
    [string]$connectionString,
    [string]$query,
    [switch]$debugSql
  )
  try {
    if ($debugSql) {
      Write-Host "Executing SQL Query:" -ForegroundColor DarkGray
      Write-Host "$query" -ForegroundColor Gray
    }
    $conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    try {
      $conn.Open()
      $cmd = $conn.CreateCommand()
      $cmd.CommandText = $query
      [void]$cmd.ExecuteNonQuery()
      return $true
    } finally {
      if ($conn.State -ne 'Closed') { $conn.Close() }
      $conn.Dispose()
    }
  } catch {
    W-Err ("sql exec fail: {0}" -f $_.Exception.Message)
    if ($debugSql) {
      Write-Host "Query that caused failure:" -ForegroundColor DarkGray
      Write-Host "$query" -ForegroundColor Yellow
    }
    return $false
  }
}


function Update-ApiResponseForBatch {
  param (
    [array]$batch,
    [array]$responseItems,
    [string]$connectionString,
    [string]$tableName
  )
  $rows = @()
  for ($i = 0; $i -lt $batch.Count; $i++) {
    $record = $batch[$i]
    $personId = $record.person_id
    $responseLine = $responseItems[$i]
    if ($responseLine -match '^\s*(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2}\.\d{2})_(.+?)\.json\s*$') {
      $datePart = $matches[1]
      $timePart = $matches[2]
      $uuid = $matches[3]
      $timestamp = "$datePart $timePart"
      try { $parsedTimestamp = [DateTime]::ParseExact($timestamp, "yyyy-MM-dd HH:mm:ss.ff", $null) } catch { $parsedTimestamp = [DateTime]::Now }
      $rows += "SELECT '$($personId.Replace("'", "''"))' AS person_id, '$($uuid.Replace("'", "''"))' AS uuid, '$($parsedTimestamp.ToString("yyyy-MM-dd HH:mm:ss.fff"))' AS timestamp"
    } else {
      W-Warn ("resp format unexpected at idx {0}: {1}" -f $i, $responseLine)
    }
  }
  if ($rows.Count -eq 0) { W-Warn "no valid entries for batch upd"; return }

  $cte = ($rows -join "`nUNION ALL`n")
  $updateQuery = @"
WITH Updates AS (
    $cte
)
UPDATE tgt
SET
    tgt.submission_status = 'sent',
    tgt.api_response = u.uuid,
    tgt.submission_timestamp = u.timestamp,
    tgt.previous_hash = tgt.current_hash,
    tgt.previous_json_payload = tgt.json_payload,
    tgt.row_state = 'unchanged'
FROM $tableName tgt
INNER JOIN Updates u ON tgt.person_id = u.person_id;
"@
  $ok = Execute-NonQuerySql -connectionString $connectionString -query $updateQuery

  if ($ok) {
    # Execute-NonQuerySql returned true|success
    Write-Host "Batch update of API response status completed." -ForegroundColor Cyan
  } else {
    Write-Host "Batch update failed (see error above)." -ForegroundColor Yellow
  }

}

function Handle-BatchFailure {
  param (
    [array]$batch,
    [string]$connectionString,
    [string]$tableName,
    [string]$errorMessage,
    [string]$detailedError,
    [string]$statusCode
  )
  $failedIndexes = [regex]::Matches($detailedError, '\[([0-9]+)\]') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  $failedIndexesSet = @{}
  foreach ($index in $failedIndexes) { $failedIndexesSet[$index] = $true }

  for ($i = 0; $i -lt $batch.Count; $i++) {
    $record = $batch[$i]
    $personId = $record.person_id
    if ($failedIndexesSet.ContainsKey([string]$i)) {
      $statusMessage = "API error ($statusCode): $errorMessage, $detailedError"
    } else {
      $statusMessage = "API error ($statusCode): $errorMessage, Record valid but batch failed"
    }
    $escapedMessage = $statusMessage -replace "'", "''"
    $updateQuery = @"
UPDATE $tableName
SET submission_status = 'error',
    api_response = '$escapedMessage'
WHERE person_id = '$personId';
"@
    # pass -debugSql to view update on console: Execute-NonQuerySql -connectionString $connectionString -query $updateQuery -debugSql
    Execute-NonQuerySql -connectionString $connectionString -query $updateQuery
    Write-Host "Logged API error for person_id '$personId': $statusMessage" -ForegroundColor Yellow
  }
}

function Update-FailedApiResponses {
  param (
    [array]$failures,
    [string]$connectionString,
    [string]$tableName
  )
  $failuresArray = ,@($failures)
  foreach ($fail in $failuresArray) {
    $personId = $fail.person_id
    $escapedResponse = $fail.response
    $updateQuery = @"
UPDATE $tableName
SET submission_status = 'error',
    api_response = '$escapedResponse'
WHERE person_id = '$personId';
"@
    # pass -debugSql to view update on console: Execute-NonQuerySql -connectionString $connectionString -query $updateQuery -debugSql
    Execute-NonQuerySql -connectionString $connectionString -query $updateQuery
    if ($personId) { Write-Host "Logged API error for person_id '$personId': $escapedResponse" -ForegroundColor Yellow }
    else { Write-Host "Logged API error for unknown person_id: $escapedResponse" -ForegroundColor Yellow }
  }
}

function Parse-ApiReply {
  param([string]$Raw,[int]$Expect)
  $items = $Raw -split '\s+' | Where-Object { $_ -match '\.json$' }
  if ($items.Count -ne $Expect) { W-Warn ("resp count {0} vs batch {1}" -f $items.Count,$Expect) }
  ,$items
}

function Send-ApiBatch {
  param (
    [array]$batch,
    [string]$endpoint,
    [hashtable]$headers,
    [string]$connectionString,
    [string]$tableName,
    [ref]$FailedResponses,
    [string]$FinalJsonPayload,
    [ref]$CumulativeDbWriteTime, # stopwatch - measure DB write time
    [int]$maxRetries = 3,
    [int]$timeout = 30 # exponential backoff: 5s -> 10s -> 20s -> 30s (capped)
  )

  # If internal test mode, dont call API (this internal simulated test)
  if ($InternalTest -or $internalTesting) {
    W-Info "Test mode: simulate send, do not call API"
    return
  }

  # Retry counters and proxy settings
  $retryCount = 0
  $delay = 5
  $proxy = Get-ProxySplat   # pick up CLI proxy settings, if any

  # Retry loop for HTTP call only
  while ($retryCount -lt $maxRetries) {

    # Make HTTP call, retry on some status codes
    try {
      $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $FinalJsonPayload -ContentType "application/json" -TimeoutSec $timeout -ErrorAction Stop @proxy
      Write-Host "Raw API response: $response"
    } catch {
      # read HTTP status and any body text for diagnostics
      $httpStatus = if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $_.Exception.Response.StatusCode.Value__ } else { "Unknown" }
      $detail = ""
      if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $detail = $reader.ReadToEnd()
      }

      # retry based on status
      switch ($httpStatus) {
        204 { $apiMsg = "No content";              $retryAllowed = $false }
        400 { $apiMsg = "Malformed Payload";       $retryAllowed = $false }
        401 { $apiMsg = "Invalid API token";       $retryAllowed = $true  }
        403 { $apiMsg = "API access disallowed";   $retryAllowed = $true  }
        413 { $apiMsg = "Payload exceeds limit";   $retryAllowed = $false }
        429 { $apiMsg = "Rate limit exceeded";     $retryAllowed = $true  }
        default { $apiMsg = "Unexpected Error: $httpStatus"; $retryAllowed = $true }
      }

      Write-Host "API request failed with HTTP status: $httpStatus ($apiMsg)" -ForegroundColor Red
      if ($detail) { W-Dim ("API error detail: {0}" -f $detail) }

      if (-not $retryAllowed) {
        # Do not retry, log failures for batch and exit loop
        W-Warn "No retry for this code. Logging failure"
        Handle-BatchFailure -batch $batch -connectionString $connectionString -tableName $tableName -errorMessage $apiMsg -detailedError $detail -statusCode $httpStatus
        break
      } elseif ($retryCount -eq ($maxRetries - 1)) {
        # Last attempt already used, log and exit
        W-Warn "Max retries reached. Logging failure"
        Handle-BatchFailure -batch $batch -connectionString $connectionString -tableName $tableName -errorMessage $apiMsg -detailedError $detail -statusCode $httpStatus
        break
      } else {

        # use server guidance if available
        $retryAfterSec = $null
        try {
          $ra = $_.Exception.Response.Headers["Retry-After"]
          if ($ra) { $retryAfterSec = [int]$ra }
        } catch { }

        if ($retryAfterSec) {
          W-Info ("Server Retry-After seen, sleeping {0}s..." -f $retryAfterSec)
          Start-Sleep -Seconds $retryAfterSec
        } else {
          # Exponential backoff + jitter, raise cap for 403 - common WAF shaping
          $cap = if ($httpStatus -eq 403) { 120 } else { 30 }
          $delay = [Math]::Min($cap, ([int]$delay * 2)) + (Get-Random -Minimum 0 -Maximum 3)
          W-Info ("Retry in {0}s..." -f $delay)
          Start-Sleep -Seconds $delay
        }

        $retryCount++
        continue  # next loop attempt
      }
    }

    # If here, HTTP call succeeded. Do post-send work
    # must not trigger another HTTP retry. Failures here are local
    try {
      $responseItems = Parse-ApiReply -Raw $response -Expect $batch.Count

      # API should return one token per item. If not, warn and skip DB update
      if ($responseItems.Count -ne $batch.Count) {
        Write-Host "Response count ($($responseItems.Count)) does not match batch count ($($batch.Count)). Skipping updates." -ForegroundColor Yellow
      } else {
        # Only write to DB when not using hard-coded test record
        if (-not $useTestRecord) {
          $dbSw = [System.Diagnostics.Stopwatch]::StartNew()
          Update-ApiResponseForBatch -batch $batch -responseItems $responseItems -connectionString $connectionString -tableName $tableName
          $dbSw.Stop()
          $CumulativeDbWriteTime.Value += $dbSw.Elapsed.TotalSeconds
        } else {
          W-Info "UseTestRecord set. Skip DB update"
        }
      }

      break  # success path, leave retry loop

    } catch {
      # Local processing failed (parse or DB update)
      # Do not retry HTTP call. Log batch as local error and exit
      W-Err ("Post-send processing failed (no retry of HTTP): {0}" -f $_.Exception.Message)
      Handle-BatchFailure -batch $batch -connectionString $connectionString -tableName $tableName -errorMessage "Local post-processing error" -detailedError $_.Exception.ToString() -statusCode "Local"
      break
    }

  } # end while retry loop

} 

function Get-PendingRecordsFromDb {
  param (
    [string]$connectionString,
    [string]$tableName,
    [bool]$usePartialPayload = $false
  )

  # Basic guard
  if (-not $tableName -or $tableName.Trim() -eq "") {
    W-Err "no table name in Get-PendingRecordsFromDb"
    return @()
  }

  # Choose the field based on mode
  if ($usePartialPayload) {
    $query = @"
SELECT person_id, partial_json_payload
FROM $tableName
WHERE (submission_status IN ('pending','error'))
  AND partial_json_payload IS NOT NULL 
  AND LTRIM(RTRIM(partial_json_payload)) <> '';
"@
  } else {
    $query = @"
SELECT person_id, json_payload
FROM $tableName
WHERE (submission_status IN ('pending','error'))
  AND json_payload IS NOT NULL 
  AND LTRIM(RTRIM(json_payload)) <> '';
"@
  }

  $JsonArray = @()

  try {
    # Open the DB connection
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()

    try {
      $command = $connection.CreateCommand()
      $command.CommandText = $query
      $reader = $command.ExecuteReader()

      try {
        while ($reader.Read()) {

          # Coerce person_id out of DBNull to $null, else to string
          $rawPid   = $reader["person_id"]
          if ($null -eq $rawPid -or $rawPid -is [System.DBNull]) {
            $personId = $null
          } else {
            $personId = [string]$rawPid
          }

          # Choose the JSON field and coerce to string safely
          $rawJsonVal = if ($usePartialPayload) { $reader["partial_json_payload"] } else { $reader["json_payload"] }
          if ($null -eq $rawJsonVal -or $rawJsonVal -is [System.DBNull]) {
            $rawJsonStr = $null
          } else {
            $rawJsonStr = [string]$rawJsonVal
          }

          # Skip empty or whitespace JSON
          if ([string]::IsNullOrWhiteSpace($rawJsonStr)) {
            $pidLabel = if ([string]::IsNullOrWhiteSpace([string]$personId)) { '<null>' } else { [string]$personId }
            W-Warn ("skip rec '{0}' null or empty JSON" -f $pidLabel)
            continue
          }

          try {
            # Parse JSON; skip if cannot parse or empty object
            $parsedJson = $rawJsonStr | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $parsedJson) {
              $pidLabel = if ([string]::IsNullOrWhiteSpace([string]$personId)) { '<null>' } else { [string]$personId }
              W-Warn ("skip rec '{0}' unparsable JSON" -f $pidLabel)
              continue
            }
            if ($parsedJson.PSObject.Properties.Count -eq 0) {
              $pidLabel = if ([string]::IsNullOrWhiteSpace([string]$personId)) { '<null>' } else { [string]$personId }
              W-Warn ("skip rec '{0}' empty JSON" -f $pidLabel)
              continue
            }

            # Enforce a usable person_id
            if ([string]::IsNullOrWhiteSpace([string]$personId)) {
              W-Warn "skip rec with NULL or blank person_id"
              continue
            }

            # Add to the array in the expected shape
            $JsonArray += [PSCustomObject]@{
              person_id = $personId
              json      = $parsedJson
            }

          } catch {
            $pidLabel = if ([string]::IsNullOrWhiteSpace([string]$personId)) { '<null>' } else { [string]$personId }
            W-Err ("json parse fail for '{0}': {1}" -f $pidLabel, $_.Exception.Message)
          }

        } # end while
      } finally {
        $reader.Close()
      }

    } finally {
      if ($connection.State -ne 'Closed') { $connection.Close() }
      $connection.Dispose()
    }

  } catch {
    W-Err ("db conn err: {0}" -f $_.Exception.Message)
  }

  # Return as array (comma ensures array even if single item)
  return ,$JsonArray
}



function Get-HardcodedTestRecord {
  # test api process with single minimal fake record
  # zero-padded la_code suffix IDs so each LA unique
  $la_code_str = ('{0:D3}' -f [int]$la_code)
  $childId     = "Fake1234$la_code_str"
  $misId       = "MIS$la_code_str"

  # minimal payload
  $payload = [ordered]@{
    la_child_id  = $childId
    mis_child_id = $misId
    child_details = [ordered]@{
      unique_pupil_number = "A123456789012"
      first_name          = "John"
      surname             = "Doe"
      date_of_birth       = "2022-06-14"
      sex                 = "M"
      ethnicity           = "WBRI"
      postcode            = "AB12 3DE"
      purge               = $false
    }
    purge = $false
  }


  # normalise to PSCustomObject
  $jsonObj = ($payload | ConvertTo-Json -Depth 10 -Compress) | ConvertFrom-Json -ErrorAction Stop

  W-Info ("test rec keys: {0}" -f ($jsonObj.PSObject.Properties.Name -join ', '))
  # return array of {person_id,json} 
  ,@([PSCustomObject]@{ person_id = $childId; json = $jsonObj })
}

function ConvertTo-CorrectJson {
  param ([array]$batch)
  $payloadBatch = @($batch | ForEach-Object { $_.json })
  if ($payloadBatch.Count -eq 1) {
    $singleJson = $payloadBatch[0] | ConvertTo-Json -Depth 20 -Compress
    return "[$singleJson]"
  } else {
    return ($payloadBatch | ConvertTo-Json -Depth 20 -Compress)
  }
}

# deltas helpers
function Prune-UnchangedElements {
  param([Parameter(Mandatory = $true)][object]$Current,[Parameter(Mandatory = $true)][object]$Previous)
  function Recursive-Prune($curr,$prev){
    $result = @{}
    foreach ($prop in $curr.PSObject.Properties) {
      $key = $prop.Name
      $currVal = $prop.Value
      $prevVal = if ($prev.PSObject.Properties[$key]) { $prev.$key } else { $null }
      if ($key -eq 'purge') { $result[$key] = $currVal; continue }
      if ($currVal -is [PSCustomObject]) {
        if ($prevVal -isnot [PSCustomObject]) { $result[$key] = $currVal }
        else {
          $sub = Recursive-Prune -curr $currVal -prev $prevVal
          if ($sub.Count -gt 0) { $result[$key] = $sub }
        }
        continue
      }
      if ($currVal -is [System.Collections.IEnumerable] -and $currVal -isnot [string]) {
        $arrayResult = @()
        $prevArray = if ($prevVal -is [System.Collections.IEnumerable]) { $prevVal } else { @() }
        foreach ($currItem in $currVal) {
          if ($currItem -is [PSCustomObject]) {
            $idProp = $currItem.PSObject.Properties | Where-Object { $_.Name -like '*_id' }
            if ($idProp) {
              $idName = $idProp.Name
              $idValue = $currItem.$idName
              $matchPrev = $prevArray | Where-Object { $_.$idName -eq $idValue }
              if ($matchPrev) {
                $diffItem = Recursive-Prune -curr $currItem -prev $matchPrev
                if ($diffItem.Count -gt 0) { $arrayResult += $diffItem }
                elseif ($currItem.PSObject.Properties.Name -contains 'purge' -and $currItem.PSObject.Properties.Count -le 2) { }
                # Unchanged, only _id + purge omit
              } else {
                # Missing from current emit purge:true with ID
                $purgeItem = @{}
                $purgeItem[$idName] = $idValue
                $purgeItem['purge'] = $true
                $arrayResult += [PSCustomObject]$purgeItem
              }
            } else { $arrayResult += $currItem }
          } elseif (-not ($prevArray -contains $currItem)) { $arrayResult += $currItem }
        }
        if ($arrayResult.Count -gt 0) { $result[$key] = $arrayResult }
        continue
      }
      if ($currVal -ne $prevVal) { $result[$key] = $currVal }
    }
    return $result
  }
  return Recursive-Prune -curr $Current -prev $Previous
}

function Generate-AllPartialPayloads {
  param([string]$connectionString,[string]$tableName)
  Write-Host "Generating all partial JSON payloads..." -ForegroundColor Cyan
  $query = "SELECT person_id, json_payload, previous_json_payload, row_state, submission_status, partial_json_payload FROM $tableName WHERE submission_status IN ('pending', 'error');"
  $records = @()
  try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $connection.Open()
    try {
      $command = $connection.CreateCommand()
      #$command.CommandTimeout = 300 increase timeout
      $command.CommandText = $query
      $reader = $command.ExecuteReader()
      try {
        while ($reader.Read()) {
          $records += [PSCustomObject]@{
            person_id             = $reader["person_id"]
            json_payload          = $reader["json_payload"]
            previous_json_payload = $reader["previous_json_payload"]
            row_state             = $reader["row_state"]
            submission_status     = $reader["submission_status"]
            partial_json_payload  = $reader["partial_json_payload"]
          }
        }
      } finally { $reader.Close() }
    } finally { $connection.Close(); $connection.Dispose() }
  } catch { W-Err ("fetch for partial gen fail: {0}" -f $_.Exception.Message); return }

  foreach ($record in $records) {
    $personId = $record.person_id
    $currStr = $record.json_payload
    $prevStr = $record.previous_json_payload

    if ($record.row_state -eq 'new' -and $record.submission_status -eq 'pending' -and $record.partial_json_payload -ne $null -and $record.partial_json_payload.Trim() -ne '') { continue }
    if (-not $currStr -or -not $prevStr) { continue }

    try {
      $current = $currStr | ConvertFrom-Json -ErrorAction Stop
      $previous = $prevStr | ConvertFrom-Json -ErrorAction Stop
      $diff = Get-JsonDifferences -current $current -previous $previous
      if (-not $diff) { continue }

      $ordered = [ordered]@{}
      # Add required identifiers first
      foreach ($key in @("la_child_id", "mis_child_id", "child_details")) { if ($current.PSObject.Properties.Name -contains $key) { $ordered[$key] = $current.$key } }
      # Add all other changed keys from the diff except purge
      foreach ($prop in $diff.PSObject.Properties) {
        if ($prop.Name -notin @("la_child_id", "mis_child_id", "child_details", "purge")) { $ordered[$prop.Name] = $prop.Value }
      }
      # Add purge last, if present
      if ($current.PSObject.Properties.Name -contains "purge") { $ordered["purge"] = $current.purge }

      $partialJson = $ordered | ConvertTo-Json -Depth 20 -Compress
      $sqlSafe = $partialJson -replace "'", "''"
      $updateQuery = @"
UPDATE $tableName
SET partial_json_payload = '$sqlSafe'
WHERE person_id = '$personId';
"@
      Execute-NonQuerySql -connectionString $connectionString -query $updateQuery
    } catch {
      W-Err ("partial gen fail for '{0}': {1}" -f $personId, $_.Exception.Message)
    }
  }
  Write-Host "Completed partial JSON generation." -ForegroundColor Gray
}

function Get-JsonDifferences {
  param([Parameter(Mandatory=$true)] $current,[Parameter(Mandatory=$true)] $previous)
  function Compare-Objects($curr,$prev){
    if ($curr -is [System.Collections.IDictionary] -and $prev -is [System.Collections.IDictionary]) {
      $diff = @{}
      foreach ($key in $curr.Keys) {
        if (-not $prev.ContainsKey($key)) { $diff[$key] = $curr[$key] }
        elseif ((Compare-Objects $curr[$key] $prev[$key]) -ne $null) {
          $sub = Compare-Objects $curr[$key] $prev[$key]
          if ($sub -ne $null) { $diff[$key] = $sub }
        }
      }
      if ($diff.Count -gt 0) { return $diff }
      return $null
    } elseif ($curr -is [System.Collections.IList] -and $prev -is [System.Collections.IList]) {
      if ($curr.Count -ne $prev.Count -or ($curr -join ',') -ne ($prev -join ',')) { return $curr }
      return $null
    } else { if ($curr -ne $prev) { return $curr }; return $null }
  }
  $difference = Compare-Objects -curr $current -prev $previous
  if ($difference -eq $null) { return @{} }
  return $difference
}

function Get-PreviousJsonPayloadFromDb {
  param([string]$connectionString,[string]$tableName,[string]$personId)
  $result = $null
  try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $connection.Open()
    try {
      $query = "SELECT previous_json_payload FROM $tableName WHERE person_id = '$personId'"
      $command = $connection.CreateCommand()
      $command.CommandText = $query
      $reader = $command.ExecuteReader()
      try {
        if ($reader.Read()) { $result = $reader["previous_json_payload"] }
      } finally { $reader.Close() }
    } finally { $connection.Close(); $connection.Dispose() }
  } catch { W-Err ("prev json fetch fail for '{0}': {1}" -f $personId, $_.Exception.Message) }
  return $result
}

function Prepare-PartialPayloads {
  param([string]$connectionString,[string]$tableName)
  Write-Host "Pre-populating missing partial payloads for fresh pending records..." -ForegroundColor Cyan
  $prepopulateQuery = @"
UPDATE $tableName
SET partial_json_payload = json_payload
WHERE submission_status = 'pending'
  AND (partial_json_payload IS NULL OR LTRIM(RTRIM(partial_json_payload)) = '');
"@
  Execute-NonQuerySql -connectionString $connectionString -query $prepopulateQuery
  Generate-AllPartialPayloads -connectionString $connectionString -tableName $tableName
  Write-Host "Completed preparation of partial payloads." -ForegroundColor Gray
}

# cfg chk
if(-not (Test-Cfg -Api $api_endpoint -Token $token_endpoint -Id $client_id -Sec $client_secret -Scope $scope -La $la_code -Table $api_data_staging_table -Server $server -Db $database)){
  exit 1
}

# Build connection string (integrated vs SQL auth)
if ($UseIntegratedSecurityDbConnection) {
  $csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
  $csb["Data Source"]            = $server
  $csb["Initial Catalog"]        = $database
  $csb["Integrated Security"]    = $true
  # optional hardening:
  $csb["Encrypt"]                = $true
  $csb["TrustServerCertificate"] = $true # still get encryption, but bypassing CA validation (if SQL Server TLS cert is self-signed)
  $connectionString = $csb.ToString()
} else {
  # protect against missing DB creds (env vars not set)
  if ([string]::IsNullOrWhiteSpace($DbUser) -or [string]::IsNullOrWhiteSpace($DbPassword)) {
    W-Err "DB credentials missing. Supply -DbUser and -DbPassword or set DB_USER/DB_PASSWORD environment variables."
    exit 1
  }

  # Build conn string with explicit TLS opt
  $csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
  $csb["Data Source"]     = $server
  $csb["Initial Catalog"] = $database

  $csb["Integrated Security"] = $false
  $csb["User ID"]             = $DbUser
  $csb["Password"]            = $DbPassword

  # TLS settings
  $csb["Encrypt"] = $true;  $csb["TrustServerCertificate"] = $true 
  ## OR 
  # $csb["Encrypt"] = $true;  $csb["TrustServerCertificate"] = $false    # needs trusted CA
  # $csb["Encrypt"] = $false                                             # not recommended

  $connectionString = $csb.ToString()

}


# fresh token + hdr
$bearer_token = Get-OAuthToken
# did we get a token ok
if (-not $bearer_token) { W-Err "Failed to retrieve OAuth token. Exiting script."; exit 1 }
$headers = New-ApiHeaders -Token $bearer_token -SupplierKey $supplier_key

# data pull
$FailedResponses = New-Object System.Collections.ArrayList
### debug: testing partial|deltas data payload json
if ($useTestRecord) {
  $JsonArray = Get-HardcodedTestRecord
  W-Info "API connection using hardcoded test data..."
} else {
  if ($usePartialPayload) {
    # prepare deltas
    $partialStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Prepare-PartialPayloads -connectionString $connectionString -tableName $api_data_staging_table
    $partialStopwatch.Stop()
  }
  # reload fresh set of valid records
  $JsonArray = Get-PendingRecordsFromDb -connectionString $connectionString -tableName $api_data_staging_table -usePartialPayload:$usePartialPayload
  if ($usePartialPayload) { W-Ok "Deltas payload mode active (using field partial_json_payload)" } else { W-Ok "Full payload mode active (using field json_payload)" }
}

W-Info ("records in API payload: {0}" -f $JsonArray.Count)
# No need to process anything if there is nothing returned from db

if (-not $JsonArray -or $JsonArray.Count -eq 0) { W-Ok "no valid records to send. skipping API submission."; $swScript.Stop(); exit 0 }

# batching / after fethching records
$totalRecords = $JsonArray.Count
$batchSize = $BatchSize
$totalBatches = [math]::Ceiling($totalRecords / $batchSize)
$cumulativeDbWriteTime = 0.0 # reset db write stopwatch

# ---- sender-side pacing (proactive rate limiting) ----
$minGapMs = 400   # def 400ms. Or LA tune 250..1500 depending on DfE response/fail behaviour
$script:lastPostAt = [datetime]::MinValue

function Wait-MinGap {
  param([int]$gapMs)

  $now = Get-Date
  $elapsed = ($now - $script:lastPostAt).TotalMilliseconds
  if ($elapsed -lt $gapMs) {
    Start-Sleep -Milliseconds ([int]($gapMs - $elapsed))
  }

  # jitter so doesn't align with gateway windows
  Start-Sleep -Milliseconds (Get-Random -Minimum 25 -Maximum 150)
  $script:lastPostAt = Get-Date
}

# Continue send logic
for ($batchIndex = 0; $batchIndex -lt $totalBatches; $batchIndex++) {
  # Loop through each batch
  $startIndex = $batchIndex * $batchSize
  $endIndex = [math]::Min($startIndex + $batchSize - 1, $totalRecords - 1)

  # Init batch slice container
  $batchSlice = @()
  for ($i = $startIndex; $i -le $endIndex; $i++) {
    # Loop records within range of batch
    # avoid out-of-range err (shouldn't normally happen)
    if ($i -ge $JsonArray.Count) { W-Warn ("idx {0} out of range, skip" -f $i); continue }
    # Get current record (person_id + json payload) for checks
    $record = $JsonArray[$i]
    $pidCheck = $record.person_id
    $jsonCheck = $record.json        
    # Check record valid: has requ fields, non-null, structured as expected
    $valid = (
      $record -ne $null -and
      $record.PSObject.Properties["person_id"] -and
      -not ($pidCheck -is [System.DBNull]) -and
      -not [string]::IsNullOrWhiteSpace([string]$pidCheck) -and
      $record.PSObject.Properties["json"] -and
      $jsonCheck -ne $null -and
      $jsonCheck.PSObject.Properties.Count -gt 0
    )

    # DEBUG
    if (-not $valid) {
      # do we have what we need to consitute a valid record? 
      $pidType = if ($null -eq $pidCheck) { 'null' } else { $pidCheck.GetType().FullName }
      W-Warn ("skip invalid rec. person_id='{0}' (type={1})" -f ([string]$pidCheck), $pidType)
    }



    # valid, add it to current batch slice, else # record not as expected
    if ($valid) { $batchSlice += $record } else { W-Warn ("skip empty or invalid rec. person_id '{0}'" -f $pidCheck) }
  }

  if ($batchSlice.Count -eq 0) { W-Warn ("no valid records in batch {0}. skip" -f ($batchIndex+1)); continue }
  W-Info ("sending batch {0} of {1}..." -f ($batchIndex + 1), $totalBatches)

  # ensure batch is valid structure 
  # incl. if single record, we need to physically/coerce wrap it within array wrapper [ ] before hitting api
  $finalPayload = ConvertTo-CorrectJson -batch $batchSlice
  ## output entire payload for verification 
  #Write-Host "final payload $($finalPayload)"   # DEBUG

  Wait-MinGap -gapMs $minGapMs # proactive pacing (incl when no errors)


  Send-ApiBatch -batch $batchSlice `
    -endpoint $api_endpoint_with_lacode `
    -headers $headers `
    -connectionString $connectionString `
    -tableName $api_data_staging_table `
    -FailedResponses ([ref]$FailedResponses) `
    -FinalJsonPayload $finalPayload `
    -CumulativeDbWriteTime ([ref]$cumulativeDbWriteTime) `
    -timeout $ApiTimeout
}

# perf
$swScript.Stop()
Write-Host ""
Write-Host "Performance summary" -ForegroundColor Blue
if ($usePartialPayload) { Write-Host ("Partial JSON generation time: {0:N2} seconds" -f $partialStopwatch.Elapsed.TotalSeconds) }
Write-Host ("DB write time                : {0:N2} seconds" -f $cumulativeDbWriteTime)
Write-Host ("Total script runtime         : {0:N2} seconds" -f $swScript.Elapsed.TotalSeconds)

# write failed
if ($FailedResponses.Count -gt 0) {
  Update-FailedApiResponses -failures $FailedResponses -connectionString $connectionString -tableName $api_data_staging_table
}

# end banner
$scriptEndStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Ended: $scriptEndStamp ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray