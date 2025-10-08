<#
Script Name: SSD API
Description:
PowerShell script to pull pre-built JSON from SSD (SQL Server), send to API, and update $api_data_staging_table.
Refresh cadence set outside this script.

Key features:
- Pulls pending JSON from $api_data_staging_table
- Sends to API or sim mode
- Marks Sent | Error | Testing
- Phase switch: full or deltas
- Batch + timeout controls

Params (via param block):
- Phase: full | deltas
- InternalTest: switch for dry-run
- UseTestRecord: switch for hard-coded sample
- BatchSize: max recs per POST
- ApiTimeout: per-call timeout (sec)

Config:
- Set $server, $database, $api_data_staging_table for your env
- OAuth cfg via $token_endpoint $client_id $client_secret $scope $supplier_key

Notes:
legacy vars mapped for compat: $usePartialPayload, $internalTesting, $useTestRecord, $batchSize, $timeoutSec

Prereqs:
- PowerShell 5.1+
- .NET SQL client or SqlServer module
- SSD schema incl $api_data_staging_table (or _anon for test)

cli examples:
- powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\phase_1_api_payload.ps1 -Phase full
- powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\phase_1_api_payload.ps1 -Phase deltas
- powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\phase_1_api_payload.ps1 -Phase full -InternalTest
- powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\phase_1_api_payload.ps1 -Phase full -UseTestRecord -BatchSize 100 -ApiTimeout 30
#>


[CmdletBinding()]
param(
  [ValidateSet('full','deltas')] [string]$Phase = 'full',  # pick payload type
  [switch]$InternalTest,                                   # simulate send
  [switch]$UseTestRecord,                                  # use hard-coded fake record
  [ValidateRange(1,100)] [int]$BatchSize = 100,            # per-batch
  [ValidateRange(5,60)]  [int]$ApiTimeout = 30             # secs
)
$VERSION = '0.4.0'
Write-Host ("CSC API staging build: v{0}" -f $VERSION)




# ----------- LA Config START -----------

# Replace details in quotes below with your LA's credentials as supplied by DfE
# from https://pp-find-and-use-an-api.education.gov.uk/ (log in)

$la_code         = "000" # Change to your 3 digit LA code
$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1" # 'Base URL' 


# From the 'Native OAuth Application-flow' block
$client_id       = "OAUTH_CLIENT_ID_CODE" # 'OAuth Client ID'
$client_secret   = "NATIVE_OAUTH_PRIMARY_KEY_CODE"  # 'Native OAuth Application-flow' - 'Primary key' or 'Secondary key'
$scope           = "OAUTH_SCOPE_LINK" # 'OAuth Scope'
$token_endpoint  = "OAUTH_TOKEN_ENDPOINT" # From the 'Native OAuth Application-flow' block - 'OAuth token endpoint'

# From 'subscription key' block
$supplier_key    = "SUBSCRIPTION_PRIMARY_KEY_CODE" # From the 'subscription key' block - 'Primary key' or 'Secondary key'


# Internal settings

# LA's db
$server = "ESLLREPORTS04V"
$database = "HDM_Local"

# local paths (optional)
$testOutputFilePath = "C:\Users\d2i\Documents\api_payload_test.json" # example
$logFile            = "C:\Users\d2i\Documents\api_temp_log.json" # example

# ----------- LA Config END -----------




# ----------- Config OVERIDE ---------------
# D2I 
# ----------- Config OVERIDE END -----------




# ----------- DEV START ---------------

# map to legacy vars from param cmdlet
$usePartialPayload = ($Phase -eq 'deltas')   # full=false, deltas=true # phase --> payload switch
$internalTesting   = [bool]$InternalTest
$useTestRecord     = [bool]$UseTestRecord
$batchSize         = $BatchSize
$timeoutSec        = $ApiTimeout

# which payload table (LA can change when ready)
$api_data_staging_table = "ssd_api_data_staging_anon"  # live: ssd_api_data_staging | test: _anon

# ----------- DEV END ---------------




# tls
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
  try {
    $resp = Invoke-RestMethod -Uri $token_endpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
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
  Execute-NonQuerySql -connectionString $connectionString -query $updateQuery
  Write-Host "Batch update of API response status completed." -ForegroundColor Cyan
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
    [ref]$CumulativeDbWriteTime, # stopwatch -monitor write time
    [int]$maxRetries = 3 # exponential backoff: 5s -> 10s -> 20s -> 30s (capped)
  )

  if ($InternalTest -or $internalTesting) {
    W-Info "test mode send sim only"
    return
  }

  $retryCount = 0
  $delay = 5
  while ($retryCount -lt $maxRetries) {
    try {
      $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $FinalJsonPayload -ContentType "application/json" -TimeoutSec $timeoutSec -ErrorAction Stop

      Write-Host "Raw API response: $response"
      $responseItems = Parse-ApiReply -Raw $response -Expect $batch.Count
      if ($responseItems.Count -ne $batch.Count) {
        Write-Host "Response count ($($responseItems.Count)) does not match batch count ($($batch.Count)). Skipping updates." -ForegroundColor Yellow
      } else {
        $dbSw = [System.Diagnostics.Stopwatch]::StartNew()
        Update-ApiResponseForBatch -batch $batch -responseItems $responseItems -connectionString $connectionString -tableName $tableName
        $dbSw.Stop()
        $CumulativeDbWriteTime.Value += $dbSw.Elapsed.TotalSeconds
      }
      break
    } catch {
      $httpStatus = if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $_.Exception.Response.StatusCode.Value__ } else { "Unknown" }
      $detail = ""
      if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $detail = $reader.ReadToEnd()
      }
      switch ($httpStatus) {
        # avoid retries/uneccessary server overheads when pointless, so not all responses initiate retry
        204 { $apiMsg = "No content"; $retryAllowed = $false }
        400 { $apiMsg = "Malformed Payload"; $retryAllowed = $false }
        401 { $apiMsg = "Invalid API token"; $retryAllowed = $true }
        403 { $apiMsg = "API access disallowed"; $retryAllowed = $true }
        413 { $apiMsg = "Payload exceeds limit"; $retryAllowed = $false }
        429 { $apiMsg = "Rate limit exceeded"; $retryAllowed = $true }
        default { $apiMsg = "Unexpected Error: $httpStatus"; $retryAllowed = $true }
      }
      Write-Host "API request failed with HTTP status: $httpStatus ($apiMsg)" -ForegroundColor Red

      # Fallback for exceptions without Response or StatusCode (e.g. TLS errors, DNS fail, etc.)
      if (-not $_.Exception.Response) {
        W-Dim ("ex type: {0}" -f $_.Exception.GetType().FullName)
        W-Dim ("ex msg : {0}" -f $_.Exception.Message)
      }
      if ($detail) { W-Dim ("api err detail: {0}" -f $detail) }

      if (-not $retryAllowed) {
        W-Warn "no retry for this code. logging fail"
        Handle-BatchFailure -batch $batch -connectionString $connectionString -tableName $tableName -errorMessage $apiMsg -detailedError $detail -statusCode $httpStatus
        break
      } elseif ($retryCount -eq ($maxRetries - 1)) {
        W-Warn "max retries reached. logging fail"
        Handle-BatchFailure -batch $batch -connectionString $connectionString -tableName $tableName -errorMessage $apiMsg -detailedError $detail -statusCode $httpStatus
        break
      } else {
        if ($httpStatus -eq 403) {
          $delay = [Math]::Min(30, $delay * 2)
        } else {
          $delay = [Math]::Min(30, $delay * 2)
        }
        $delay += Get-Random -Minimum 0 -Maximum 3
        W-Info ("retry in {0}s..." -f $delay)
        Start-Sleep -Seconds $delay
        $retryCount++
      }
    }
  }
}

function Get-PendingRecordsFromDb {
  param (
    [string]$connectionString,
    [string]$tableName,
    [bool]$usePartialPayload = $false
  )

  if (-not $tableName -or $tableName.Trim() -eq "") { W-Err "no table name in Get-PendingRecordsFromDb"; return @() }

  if ($usePartialPayload) {
    # switch between whether process uses partial_json_payload or json_payload field to obtain payload records
    # Dev note. Refactor needed here if re-applying casting.  
    # AND TRY_CAST(LTRIM(RTRIM(partial_json_payload)) AS NVARCHAR(MAX)) <> ''

    $query = @"
SELECT person_id, partial_json_payload
FROM $tableName
WHERE (submission_status = 'pending' OR submission_status = 'error')
AND partial_json_payload IS NOT NULL 
AND LTRIM(RTRIM(partial_json_payload)) `<>` '';
"@
  } else {
  # AND TRY_CAST(json_payload AS NVARCHAR(MAX)) <> '';    
  $query = @"
SELECT person_id, json_payload
FROM $tableName
WHERE (submission_status = 'pending' OR submission_status = 'error')
AND json_payload IS NOT NULL 
AND LTRIM(RTRIM(json_payload)) `<>` '';
"@
  }

  $JsonArray = @()
  try {
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()
    try {
      $command = $connection.CreateCommand()
      $command.CommandText = $query
      $reader = $command.ExecuteReader()
      try {
        while ($reader.Read()) {
          $personId = $reader["person_id"]
          $rawJson = if ($usePartialPayload) { $reader["partial_json_payload"] } else { $reader["json_payload"] }
          if (-not $rawJson -or $rawJson.Trim() -eq "") { W-Warn ("skip rec '{0}' null or empty JSON" -f $personId); continue }
          try {
            $parsedJson = $rawJson | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $parsedJson) { W-Warn ("skip rec '{0}' unparsable JSON" -f $personId); continue }
            if ($parsedJson.PSObject.Properties.Count -eq 0) { W-Warn ("skip rec '{0}' empty JSON" -f $personId); continue }
            $JsonArray += [PSCustomObject]@{ person_id = $personId; json = $parsedJson }
          } catch {
            W-Err ("json parse fail for '{0}': {1}" -f $personId, $_.Exception.Message)
          }
        }
      } finally {
        $reader.Close()
      }
    } finally {
      $connection.Close()
      $connection.Dispose()
    }
  } catch {
    W-Err ("db conn err: {0}" -f $_.Exception.Message)
  }
  return ,$JsonArray
}

function Get-HardcodedTestRecord {
  # test api process with hard-coded minimal single fake record
  $jsonString = @'
    {
      "la_child_id": "f96f473f1feb4d6da3379d06670844fd",
      "mis_child_id": "nXLdcNLOkg1nS4LnEg0",
      "child_details": {
        "unique_pupil_number": "X5GLGl9mWSNjM",
        "former_unique_pupil_number": "DEF0123456789",
        "unique_pupil_number_unknown_reason": "UN1",
        "first_name": "John",
        "surname": "Doe",
        "date_of_birth": "2022-06-14",
        "expected_date_of_birth": "2022-06-14",
        "sex": "M",
        "ethnicity": "WBRI",
        "disabilities": ["HAND", "VIS"],
        "postcode": "AB12 3DE",
        "uasc_flag": true,
        "uasc_end_date": "2022-06-14",
        "purge": false
      },
      "purge": false
    }
'@
  $parsedJson = $jsonString | ConvertFrom-Json -ErrorAction Stop
  W-Info ("test rec keys: {0}" -f ($parsedJson.PSObject.Properties.Name -join ', '))
  return ,@([PSCustomObject]@{ person_id = "f96f473f1feb4d6da3379d06670844fd"; json = $parsedJson })
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

# conn str
# potentially move to environment var
$connectionString = "Server=$server;Database=$database;Integrated Security=True;"

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
# we don't eed to process anything if there is nothing returned from db

if (-not $JsonArray -or $JsonArray.Count -eq 0) { W-Ok "no valid records to send. skipping API submission."; $swScript.Stop(); exit 0 }

# batching / after fethching records
$totalRecords = $JsonArray.Count
$batchSize = $BatchSize
$totalBatches = [math]::Ceiling($totalRecords / $batchSize)
$cumulativeDbWriteTime = 0.0 # reset db write stopwatch

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
      $record.PSObject.Properties["json"] -and
      $pidCheck -ne $null -and
      $pidCheck -ne "" -and
      $jsonCheck -ne $null -and
      $jsonCheck.PSObject.Properties.Count -gt 0
    )

    # valid, add it to current batch slice, else # record not as expected
    if ($valid) { $batchSlice += $record } else { W-Warn ("skip empty or invalid rec. person_id '{0}'" -f $pidCheck) }
  }

  if ($batchSlice.Count -eq 0) { W-Warn ("no valid records in batch {0}. skip" -f ($batchIndex+1)); continue }
  W-Info ("sending batch {0} of {1}..." -f ($batchIndex + 1), $totalBatches)

    # ensure batch is valid structure 
    # incl. if single record, we need to physically/coerce wrap it within array wrapper [ ] before hitting api

  $finalPayload = ConvertTo-CorrectJson -batch $batchSlice
  ## output entire payload for verification 
  #Write-Host "final payload $($finalPayload)"   # debug

  Send-ApiBatch -batch $batchSlice `
    -endpoint $api_endpoint_with_lacode `
    -headers $headers `
    -connectionString $connectionString `
    -tableName $api_data_staging_table `
    -FailedResponses ([ref]$FailedResponses) `
    -FinalJsonPayload $finalPayload `
    -CumulativeDbWriteTime ([ref]$cumulativeDbWriteTime)

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
