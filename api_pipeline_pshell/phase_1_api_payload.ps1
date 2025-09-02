
<#

Script Name: SSD API
Description:
    PowerShell script automates extraction of pre-defined JSON payload from SSD (CMS (SQL)Server instance), 
    submitting payload to API, updating submission status within $api_data_staging_table in SSD.
    Frequency of data refresh within $api_data_staging_table, execution of this script set by pilot LA,
    not defined/set/automated within this process. 

Key Features:
- Extracts pending JSON payload from specified/pre-populated $api_data_staging_table
- Sends data to defined API endpoint OR simulates process for testing
- Updates submission statuses on SSD $api_data_staging_table: Sent, Error, or Testing as submission history

Parameters:
- $internalTesting: Boolean flag to toggle testing mode. When true, no data sent to API|send is simulated
- $server: CMS (SQL) Server instance name
- $database: DB name
- $api_data_staging_table: Table containing JSON payloads, status and submission info
- $url: API endpoint
- $token: Authentication token for API

Usage:
- Set $internalTesting to true during testing to simulate API call without sending data to API endpoint
- Update $server, $database to match LA environment

Prerequisites:
- PowerShell 5.1 or later (permissions for execution)
- .net accessible (db connection) or SqlServer PowerShell module installed
- (SQL)Server with SSD structure deployed Incl. populated api_data_staging_table(_anon in test) non-core table


Author: D2I
Version: 0.3.5
Last Updated: 02/09/25
#>


# DEV | PRE-TEST
$scriptStartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Started: $scriptStartTime ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray


# IMPORTANT 
# Set $true values if testing locally

# Test-mode flags
$internalTesting = $false # Set $false to (re)enable external API calls
$useTestRecord = $false  # $false creates payload from DB live|anon staging data | $true creates payload from hard-coded test data


# Temp local logging (failsafe)
# LA's|Local tests should comment out or change to valid local path
$testOutputFilePath = "C:\Users\RobertHa\Documents\api_payload_test.json"  
$logFile = "C:\Users\RobertHa\Documents\api_temp_log.json"


$scriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()



# Payload switch 
# $false == json_payload         - phase 1 : full records payload(db field: json_payload)
# $true  == partial_json_payload - phase 2 : partial|deltas(db field: partial_json_payload)
$usePartialPayload = $true

## end DEV | PRE-TEST



## Connectivity
##

# Db connection
$server = "ESLLREPORTS04V" 
$database = "HDM_Local"
$api_data_staging_table = "ssd_api_data_staging_anon"  # IMPORTANT - LIVE: ssd_api_data_staging | TESTING : ssd_api_data_staging_anon


# API Configuration
# DfE supplied details from https://pp-find-and-use-an-api.education.gov.uk/api/83

$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1"
$token_endpoint = "DfE supplied detail"

# OAuth Credentials
$client_id = "DfE supplied detail"
$client_secret = "DfE supplied detail"
$scope = "DfE supplied detail"

# Subscription Key
$supplier_key = "DfE supplied detail"


## LA specifics
##

# Endpoint with LA Code
$la_code = 845 
$api_endpoint_with_lacode = "$api_endpoint/children_social_care_data/$la_code/children"
Write-Host "Final API Endpoint: $api_endpoint_with_lacode"


## Extract payload staging data
##

# Query unsubmitted|pending person/child json payload(s)
# we include error status records as these have been loaded but previously rejected within a failed batch and therefore need to be re-sent
$query = "SELECT person_id, json_payload, previous_json_payload, partial_json_payload FROM $api_data_staging_table WHERE submission_status = 'pending' OR submission_status = 'error';"




## Main processing 
##

function Get-OAuthToken {

    $body = @{
        client_id     = $client_id 
        client_secret = $client_secret 
        scope         = $scope 
        grant_type    = "client_credentials"
    }

    try {
        $response = Invoke-RestMethod -Uri $token_endpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        return $response.access_token
    } catch {
        Write-Host "Error retrieving OAuth token: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}
# fresh token
$bearer_token = Get-OAuthToken

# did we get a token ok
if (-not $bearer_token) {
    Write-Host "Failed to retrieve OAuth token. Exiting script." -ForegroundColor Red
    exit
}


# Guidance states SupplierKey must be supplied
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $bearer_token"
    "SupplierKey"   = $supplier_key
}




function Execute-NonQuerySql {
    param (
        [string]$connectionString,
        [string]$query,
        [switch]$debugSql  # optional: pass -debugSql to show query
    )
    try {
        if ($debugSql) {
            Write-Host "Executing SQL Query:" -ForegroundColor DarkGray
            Write-Host "$query" -ForegroundColor Gray
        }

        $conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $conn.Open()
        $cmd = $conn.CreateCommand()
        #$cmd.CommandTimeout = 300  # 5 min
        $cmd.CommandText = $query
        [void]$cmd.ExecuteNonQuery()
        $conn.Close()
    } catch {
        Write-Host "SQL execution failed: $($_.Exception.Message)" -ForegroundColor Red
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

            try {
                $parsedTimestamp = [DateTime]::ParseExact($timestamp, "yyyy-MM-dd HH:mm:ss.ff", $null)
            } catch {
                $parsedTimestamp = [DateTime]::Now
            }

            $rows += "SELECT '$($personId.Replace("'", "''"))' AS person_id, '$($uuid.Replace("'", "''"))' AS uuid, '$($parsedTimestamp.ToString("yyyy-MM-dd HH:mm:ss.fff"))' AS timestamp"
        } else {
            Write-Host "Unexpected response format for record #($i): $responseLine" -ForegroundColor Yellow
        }
    }

    if ($rows.Count -eq 0) {
        Write-Host "No valid entries for batch update." -ForegroundColor Yellow
        return
    }

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

        if ($personId) {
            Write-Host "Logged API error for person_id '$personId': $escapedResponse" -ForegroundColor Yellow

        } else {
            Write-Host "Logged API error for unknown person_id: $escapedResponse" -ForegroundColor Yellow

        }
    }
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
        [ref]$CumulativeDbWriteTime, # stopwatch to monitor write time
        [int]$maxRetries = 3,
        [int]$timeout = 30 # exponential backoff: 5s -> 10s -> 20s -> 30s (capped)
    )

    $retryCount = 0
    $initialDelay = 5
    $retryDelay = $initialDelay


    while ($retryCount -lt $maxRetries) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $FinalJsonPayload -ContentType "application/json" -TimeoutSec $timeout

            Write-Host "Raw API response: $response"

            $responseItems = $response -split '\s+'

            if ($responseItems.Count -ne $batch.Count) {
                Write-Host "Response count ($($responseItems.Count)) does not match batch count ($($batch.Count)). Skipping updates." -ForegroundColor Yellow
            } else {

                $dbWriteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Update-ApiResponseForBatch -batch $batch -responseItems $responseItems -connectionString $connectionString -tableName $tableName
                $dbWriteStopwatch.Stop()
                $CumulativeDbWriteTime.Value += $dbWriteStopwatch.Elapsed.TotalSeconds # log stopwatch over each batch

            }

            break

        } catch {
            $httpStatus = if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $_.Exception.Response.StatusCode.Value__
            } else {
                "Unknown"
            }

            $detailedErrorMessage = ""
            if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $detailedErrorMessage = $reader.ReadToEnd()
            }

            switch ($httpStatus) {
                # avoid retries/uneccessary server overheads when pointless, so not all responses initiate retry
                204 { $api_response_message = "No content"; $retryAllowed = $false }
                400 { $api_response_message = "Malformed Payload"; $retryAllowed = $false }
                401 { $api_response_message = "Invalid API token"; $retryAllowed = $true }
                403 { $api_response_message = "API access disallowed"; $retryAllowed = $true }
                413 { $api_response_message = "Payload exceeds limit"; $retryAllowed = $false }
                429 { $api_response_message = "Rate limit exceeded"; $retryAllowed = $true }
                default { $api_response_message = "Unexpected Error: $httpStatus"; $retryAllowed = $true }
            }

            Write-Host "API request failed with HTTP status: $httpStatus ($api_response_message)" -ForegroundColor Red

            # Fallback for exceptions without Response or StatusCode (e.g. TLS errors, DNS fail, etc.)
            if (-not $_.Exception.Response) {
                Write-Host "Exception type: $($_.Exception.GetType().FullName)" -ForegroundColor DarkYellow
                Write-Host "Raw exception message: $($_.Exception.Message)" -ForegroundColor DarkYellow
            }


            if ($detailedErrorMessage) {
                Write-Host "API error detail: $detailedErrorMessage" -ForegroundColor DarkGray
            }

            if (-not $retryAllowed) {
                Write-Host "Retry not permitted for this status code. Logging failure." -ForegroundColor Yellow
                Handle-BatchFailure -batch $batch `
                                    -connectionString $connectionString `
                                    -tableName $tableName `
                                    -errorMessage $api_response_message `
                                    -detailedError $detailedErrorMessage `
                                    -statusCode $httpStatus
                break
            } elseif ($retryCount -eq ($maxRetries - 1)) {
                Write-Host "Max retries reached. Logging failure." -ForegroundColor Yellow
                Handle-BatchFailure -batch $batch `
                                    -connectionString $connectionString `
                                    -tableName $tableName `
                                    -errorMessage $api_response_message `
                                    -detailedError $detailedErrorMessage `
                                    -statusCode $httpStatus
                break
            } else {
                if ($httpStatus -eq 403) {
                    # 403 responses retry, using exponential backoff: 5s -> 10s -> 20s -> 30s (cap)
                    $retryDelay = [Math]::Min(30, $retryDelay * 2)
                    Write-Host "403 received, applying exponential backoff, retrying in $retryDelay seconds..." -ForegroundColor Magenta
                } else {
                    Write-Host "Retrying in $retryDelay seconds..."
                    $retryDelay *= 2
                }

                Start-Sleep -Seconds $retryDelay
                $retryCount++
            }
        }
    }

    # Reset retry delay for next batch
    $retryDelay = $initialDelay
}





function Get-PendingRecordsFromDb {
    param (
        [string]$connectionString,
        [string]$tableName,
        [bool]$usePartialPayload = $false
    )

    if (-not $tableName -or $tableName.Trim() -eq "") {
        Write-Host "No table name specified for Get-PendingRecordsFromDb" -ForegroundColor Red
        return @()
    }

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

        $command = $connection.CreateCommand()
        $command.CommandText = $query
        $reader = $command.ExecuteReader()

    
        while ($reader.Read()) {
            $personId = $reader["person_id"]

            $rawJson = if ($usePartialPayload) {
                $reader["partial_json_payload"]
            } else {
                $reader["json_payload"]
            }

            if (-not $rawJson -or $rawJson.Trim() -eq "") {
                Write-Host "Skipping record, person_id '$personId' has NULL or empty JSON" -ForegroundColor Yellow
                continue
            }

            try {
                $parsedJson = $rawJson | ConvertFrom-Json -ErrorAction Stop

                if ($null -eq $parsedJson) {
                    Write-Host "Skipping record, person_id '$personId' has unparsable JSON" -ForegroundColor Yellow
                    continue
                }

                if ($parsedJson.PSObject.Properties.Count -eq 0) {
                    Write-Host "Skipping record, person_id '$personId' has empty parsed JSON (no properties)" -ForegroundColor Yellow
                    continue
                }

                $record = [PSCustomObject]@{
                    person_id = $personId
                    json      = $parsedJson
                }

                $JsonArray += $record
            } catch {
                Write-Host "Failed to parse JSON for person_id '$personId': $($_.Exception.Message)" -ForegroundColor Red
            }
        }


        $reader.Close()
        $connection.Close()
    } catch {
        Write-Host "Error connecting to SQL Server: $($_.Exception.Message)" -ForegroundColor Red
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
    Write-Host "Keys after parsing test record: $($parsedJson.PSObject.Properties.Name -join ', ')"

    return ,@([PSCustomObject]@{
        person_id = "f96f473f1feb4d6da3379d06670844fd"
        json      = $parsedJson
    })
}



function ConvertTo-CorrectJson {
    param (
        [array]$batch
    )

    $payloadBatch = @($batch | ForEach-Object { $_.json })

    if ($payloadBatch.Count -eq 1) {
        # Convert single object to JSON, then wrap with [ and ]
        $singleJson = $payloadBatch[0] | ConvertTo-Json -Depth 20 -Compress
        return "[$singleJson]"
    } else {
        return ($payloadBatch | ConvertTo-Json -Depth 20 -Compress)
    }
}




## Main processing 
## deltas payload 

function Prune-UnchangedElements {
    param (
        [Parameter(Mandatory = $true)][object]$Current,
        [Parameter(Mandatory = $true)][object]$Previous
    )

    function Recursive-Prune($curr, $prev) {
        $result = @{}

        foreach ($prop in $curr.PSObject.Properties) {
            $key = $prop.Name
            $currVal = $prop.Value
            $prevVal = $null
            if ($prev.PSObject.Properties[$key]) {
                $prevVal = $prev.$key
            }

            if ($key -eq 'purge') {
                $result[$key] = $currVal
                continue
            }

            if ($currVal -is [PSCustomObject]) {
                if ($prevVal -isnot [PSCustomObject]) {
                    $result[$key] = $currVal
                } else {
                    $subResult = Recursive-Prune -curr $currVal -prev $prevVal
                    if ($subResult.Count -gt 0) {
                        $result[$key] = $subResult
                    }
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
                            $matchingPrevItem = $prevArray | Where-Object { $_.$idName -eq $idValue }

                            if ($matchingPrevItem) {
                                $diffItem = Recursive-Prune -curr $currItem -prev $matchingPrevItem
                                if ($diffItem.Count -gt 0) {
                                    $arrayResult += $diffItem
                                } elseif ($currItem.PSObject.Properties.Name -contains 'purge' -and $currItem.PSObject.Properties.Count -le 2) {
                                    # Unchanged, only _id + purge omit
                                }
                            } else {
                                # Missing from current emit purge:true with ID
                                $purgeItem = @{}
                                $purgeItem[$idName] = $idValue
                                $purgeItem['purge'] = $true
                                $arrayResult += [PSCustomObject]$purgeItem
                            }
                        } else {
                            $arrayResult += $currItem
                        }
                    } elseif (-not ($prevArray -contains $currItem)) {
                        $arrayResult += $currItem
                    }
                }

                if ($arrayResult.Count -gt 0) {
                    $result[$key] = $arrayResult
                }
                continue
            }

            if ($currVal -ne $prevVal) {
                $result[$key] = $currVal
            }
        }

        return $result
    }

    return Recursive-Prune -curr $Current -prev $Previous
}





function Generate-AllPartialPayloads {
    param (
        [string]$connectionString,
        [string]$tableName
    )

    Write-Host "Generating all partial JSON payloads..." -ForegroundColor Cyan

    $query = "SELECT person_id, json_payload, previous_json_payload, row_state, submission_status, partial_json_payload FROM $tableName WHERE submission_status IN ('pending', 'error');"
    $records = @()

    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        $command = $connection.CreateCommand()
        #$command.CommandTimeout = 300 increase timeout

        $command.CommandText = $query
        $reader = $command.ExecuteReader()

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

        $reader.Close()
        $connection.Close()
    } catch {
        Write-Host "Failed to fetch records for partial generation: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    foreach ($record in $records) {
        $personId = $record.person_id 
        $currStr = $record.json_payload
        $prevStr = $record.previous_json_payload

        if ($record.row_state -eq 'new' -and $record.submission_status -eq 'pending' -and $record.partial_json_payload -ne $null -and $record.partial_json_payload.Trim() -ne '') {
            continue
        }

        if (-not $currStr -or -not $prevStr) {
            continue
        }

        try {
            $current = $currStr | ConvertFrom-Json -ErrorAction Stop
            $previous = $prevStr | ConvertFrom-Json -ErrorAction Stop
            $diff = Get-JsonDifferences -current $current -previous $previous

            if (-not $diff) {
                continue
            }

            $orderedPartial = [ordered]@{}

            # Add required identifiers first
            foreach ($key in @("la_child_id", "mis_child_id", "child_details")) {
                if ($current.PSObject.Properties.Name -contains $key) {
                    $orderedPartial[$key] = $current.$key
                }
            }

            # Add all other changed keys from the diff except purge
            foreach ($prop in $diff.PSObject.Properties) {
                if ($prop.Name -notin @("la_child_id", "mis_child_id", "child_details", "purge")) {
                    $orderedPartial[$prop.Name] = $prop.Value
                }
            }

            # Add purge last, if present
            if ($current.PSObject.Properties.Name -contains "purge") {
                $orderedPartial["purge"] = $current.purge
            }

            $partialJson = $orderedPartial | ConvertTo-Json -Depth 20 -Compress
            $sqlSafePartialJson = $partialJson -replace "'", "''"

            $updateQuery = @"
UPDATE $tableName
SET partial_json_payload = '$sqlSafePartialJson'
WHERE person_id = '$personId';
"@
            Execute-NonQuerySql -connectionString $connectionString -query $updateQuery
        } catch {
            Write-Host "Failed partial for person_id '$personId': $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "Completed partial JSON generation." -ForegroundColor Gray
}





function Get-JsonDifferences {
    param (
        [Parameter(Mandatory = $true)] $current,
        [Parameter(Mandatory = $true)] $previous
    )

    function Compare-Objects($curr, $prev) {
        if ($curr -is [System.Collections.IDictionary] -and $prev -is [System.Collections.IDictionary]) {
            $diff = @{}
            foreach ($key in $curr.Keys) {
                if (-not $prev.ContainsKey($key)) {
                    $diff[$key] = $curr[$key]
                } elseif ((Compare-Objects $curr[$key] $prev[$key]) -ne $null) {
                    $subDiff = Compare-Objects $curr[$key] $prev[$key]
                    if ($subDiff -ne $null) { $diff[$key] = $subDiff }
                }
            }
            if ($diff.Count -gt 0) { return $diff }
            return $null
        } elseif ($curr -is [System.Collections.IList] -and $prev -is [System.Collections.IList]) {
            if ($curr.Count -ne $prev.Count -or ($curr -join ',') -ne ($prev -join ',')) {
                return $curr
            }
            return $null
        } else {
            if ($curr -ne $prev) { return $curr }
            return $null
        }
    }

    $difference = Compare-Objects -curr $current -prev $previous
    if ($difference -eq $null) { return @{} }
    return $difference
}





function Get-PreviousJsonPayloadFromDb {
    param (
        [string]$connectionString,
        [string]$tableName,
        [string]$personId
    )

    $result = $null

    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        $query = "SELECT previous_json_payload FROM $tableName WHERE person_id = '$personId'"
        $command = $connection.CreateCommand()
        $command.CommandText = $query

        $reader = $command.ExecuteReader()

        if ($reader.Read()) {
            $result = $reader["previous_json_payload"]
        }

        $reader.Close()
        $connection.Close()
    } catch {
        Write-Host "Failed to fetch previous JSON for person_id '$personId': $($_.Exception.Message)" -ForegroundColor Red
    }

    return $result
}




function Prepare-PartialPayloads {
    param (
        [string]$connectionString,
        [string]$tableName
    )

    Write-Host "Pre-populating missing partial payloads for fresh pending records..." -ForegroundColor Cyan

    # Prepopulate missing deltas (e.g. would occur if this was first run, or on new records)
    $prepopulateQuery = @"
UPDATE $tableName
SET partial_json_payload = json_payload
WHERE submission_status = 'pending'
  AND (partial_json_payload IS NULL OR LTRIM(RTRIM(partial_json_payload)) = '');
"@
    Execute-NonQuerySql -connectionString $connectionString -query $prepopulateQuery

    # Generate deltas
    Generate-AllPartialPayloads -connectionString $connectionString -tableName $tableName

    Write-Host "Completed preparation of partial payloads." -ForegroundColor Gray
}

## deltas payload related functions end 







## Main processing 


## debug
## Initial connection test option - send single minimal test record
## $useTestRecord set to $false when ready to pull data direct from DB, otherwise sends hard-coded test record

# define payload as either i OR ii:
# i) hard-coded single data record 
# ii) payload from CMS db/data staging table (with $usePartialPayload flag to define whether full or deltas payload)

$scriptStartTime = Get-Date
$FailedResponses = New-Object System.Collections.ArrayList # track failed API responses for logging

# potentially move to environment var
$connectionString = "Server=$server;Database=$database;Integrated Security=True;"


### debug: testing partial|deltas data payload json

if ($useTestRecord) {
    $JsonArray = Get-HardcodedTestRecord
    Write-Host "API connection using hardcoded test data..."
} else {
    if ($usePartialPayload) {

        # prepare deltas
        $partialStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        Prepare-PartialPayloads -connectionString $connectionString -tableName $api_data_staging_table
        $partialStopwatch.Stop()
    }

    # reload fresh set of valid records
    $JsonArray = Get-PendingRecordsFromDb -connectionString $connectionString -tableName $api_data_staging_table -usePartialPayload:$usePartialPayload

    if ($usePartialPayload) {
        Write-Host "Deltas payload mode active (using field partial_json_payload)" -ForegroundColor Green
    } else {
        Write-Host "Full payload mode active (using field json_payload)" -ForegroundColor Green
    }
}


Write-Host "Number of records in API payload: $($JsonArray.Count)"
# we don't eed to process anything if there is nothing returned from db
if (-not $JsonArray -or $JsonArray.Count -eq 0) {
    Write-Host "No valid records to send. Skipping API submission." -ForegroundColor Green
    return
}


# AFTER fetching records
$totalRecords = $JsonArray.Count
$batchSize = 100
$totalBatches = [math]::Ceiling($totalRecords / $batchSize)

$cumulativeDbWriteTime = 0.0 # reset db write stopwatch


# Continue with sending logic
for ($batchIndex = 0; $batchIndex -lt $totalBatches; $batchIndex++) {
    # Loop through each batch

    # find start and end index for current batch
    $startIndex = $batchIndex * $batchSize
    $endIndex = [math]::Min($startIndex + $batchSize - 1, $totalRecords - 1)

    # Init batch slice container
    $batchSlice = @()
    for ($i = $startIndex; $i -le $endIndex; $i++) {
        # Loop records within range of batch
        if ($i -ge $JsonArray.Count) {
            # avoid out-of-range err (shouldn't normally happen)
            Write-Host "Index $i out of range of JsonArray (Count = $($JsonArray.Count)). Skipping." -ForegroundColor Yellow
            continue
        }

        # Get current record (person_id + json payload) for checks
        $record = $JsonArray[$i]
        $pidCheck = $record.person_id
        $jsonCheck = $record.json

        # Check record valid: has requ fields, non-null, and structured as we expect
        $valid = (
                $record -ne $null -and
                $record.PSObject.Properties["person_id"] -and
                $record.PSObject.Properties["json"] -and
                $pidCheck -ne $null -and
                $pidCheck -ne "" -and
                $jsonCheck -ne $null -and
                $jsonCheck.PSObject.Properties.Count -gt 0
            )


        if ($valid) {
            # valid, add it to the current batch slice
            $batchSlice += $record
        } else {
            # record not as expected
            Write-Host "Skipping empty or invalid record during batch slice. person_id '$pidCheck'" -ForegroundColor Yellow
        }
    }



    if ($batchSlice.Count -eq 0) {
        Write-Host "No valid records in batch $($batchIndex + 1). Skipping this batch"

        continue
    }

    Write-Host "Sending batch $($batchIndex + 1) of $totalBatches..."

    # ensure batch is valid structure 
    # incl. if single record, we need to physically/coerce wrap it within array wrapper [ ] before hitting api
    $finalPayload = ConvertTo-CorrectJson -batch $batchSlice


    ## debug
    ## output the entire payload for verification 
    #Write-Host "final payload $($finalPayload)" 


    <#
    .NOTES
    pipeline separates logical data from serialised transmission format:

    - $batch contains PShell objs(structured, parsed JSON) ready for validation chks and logging
    - $FinalJsonPayload(generate via ConvertTo-CorrectJson), packages a clean, [ ] wrapped JSON array for POST
    - separation gives stability when handling 1 vs multiple records, towards more robust retry/error

    ApiBatch params reference:
                -batch $batchSlice # current batch of valid records - PShell objs(structured), for matching IDs, updating DB
                -endpoint $api_endpoint_with_lacode # API endpoint URL
                -headers $headers # Hashtable of HTTP headers, incl auth/token
                -connectionString $connectionString # SQL Server connection string for DB update after API response
                -tableName $api_data_staging_table # ssd extract data staging table + api response status tracking
                -FailedResponses ([ref]$FailedResponses) # failed responses logging
                -FinalJsonPayload $finalPayload # JSON string (ready to POST) for API request payload
    #>


    Write-Host $connectionString

    # # DEBUG:
    # # Uncomment to enable secondary level of assurance that data only leaves LA when user explicitly acknowledges via y/n
    # if (-not $script:confirmedSend) {
    #     # build a brief summary
    #     $sourceKind = if ($useTestRecord) {
    #         "hard coded test record"
    #     } else {
    #         "database table $api_data_staging_table, field " + $(if ($usePartialPayload) { "partial_json_payload" } else { "json_payload" })
    #     }
    #     $sampleIds = ($batchSlice | ForEach-Object { $_.person_id } | Where-Object { $_ } | Select-Object -First 5)
    #     $sampleText = if ($sampleIds) { ($sampleIds -join ", ") } else { "none" }

    #     Write-Host ""
    #     Write-Host "Send|batch summary" -ForegroundColor Cyan
    #     Write-Host ("Endpoint: {0}" -f $api_endpoint_with_lacode)
    #     Write-Host ("Total records to send: {0} across {1} batches of up to {2}" -f $totalRecords, $totalBatches, $batchSize)
    #     Write-Host ("This batch size: {0}" -f $batchSlice.Count)
    #     Write-Host ("Source: {0}" -f $sourceKind) -ForegroundColor Red
    #     Write-Host ("Sample person_id(s): {0}" -f $sampleText)
    #     Write-Host "--------------------------------------------------------------------------" -ForegroundColor Cyan
    #     Write-Host ""

    #     $ans = Read-Host "Proceed to send now (y/n)?"
    #     if ($ans -notmatch '^(?i)y(es)?$') {
    #         Write-Host "Send aborted by user." -ForegroundColor Yellow
    #         return
    #     }
    #     $script:confirmedSend = $true
    # }


    Send-ApiBatch -batch $batchSlice `
                  -endpoint $api_endpoint_with_lacode `
                  -headers $headers `
                  -connectionString $connectionString `
                  -tableName $api_data_staging_table `
                  -FailedResponses ([ref]$FailedResponses) `
                  -FinalJsonPayload $finalPayload `
                  -CumulativeDbWriteTime ([ref]$cumulativeDbWriteTime)

}


$scriptStopwatch.Stop()

Write-Host ""
Write-Host "Performance summary" -ForegroundColor Blue
if ($usePartialPayload) {
    Write-Host ("Partial JSON generation time: {0:N2} seconds" -f $partialStopwatch.Elapsed.TotalSeconds)
}
Write-Host ("DB write time                : {0:N2} seconds" -f $cumulativeDbWriteTime)
Write-Host ("Total script runtime         : {0:N2} seconds" -f $scriptStopwatch.Elapsed.TotalSeconds)




if ($FailedResponses.Count -gt 0) {
    Update-FailedApiResponses -failures $FailedResponses -connectionString $connectionString -tableName $api_data_staging_table
}

