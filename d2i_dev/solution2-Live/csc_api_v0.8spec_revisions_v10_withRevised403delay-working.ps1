
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
Version: 0.3.4
Last Updated: 010425
#>


# DEV ONLY: 
$scriptStartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Started: $scriptStartTime ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray




# Test mode flags
$internalTesting = $false # Set $false to (re)enable external API calls
$useTestRecord = $false  # $false creates payload from DB live|anon staging data | $true creates payload from hard-coded test data - (can|should be used when $internalTesting = $false)
$testOutputFilePath = "C:\Users\RobertHa\Documents\api_payload_test.json"  


# Connection
$server = "ESLLREPORTS04V" 
$database = "HDM_Local"
$api_data_staging_table = "ssd_api_data_staging_anon"  # IMPORTANT - LIVE: ssd_api_data_staging | TESTING : ssd_api_data_staging_anon


# API Configuration
$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1"
$token_endpoint = "https://login.microsoftonline.com/cc0e4d98-b9f9-4d58-821f-973eb69f19b7/oauth2/v2.0/token"

# OAuth Credentials
$client_id = "fe28c5a9-ea4f-4347-b419-189eb761fa42" 
$client_secret = "mR_8Q~G~Wdm2XQ2E8-_hr0fS5FKEns4wHNLtbdw7" 
$scope = "api://children-in-social-care-data-receiver-test-1-live_6b1907e1-e633-497d-ac74-155ab528bc17/.default"

# Subscription Key
$supplier_key = "6736ad89172548dcaa3529896892ab3f"

# Endpoint with LA Code
$la_code = 845 
$api_endpoint_with_lacode = "$api_endpoint/children_social_care_data/$la_code/children"
Write-Host "🔗 Final API Endpoint: $api_endpoint_with_lacode"


# Temp local logging (failsafe)
$logFile = "C:\Users\RobertHa\Documents\api_temp_log.json"



# Query unsubmitted|pending person/child json payload(s)
# we include error status records as these have been loaded but previously rejected within a failed batch
$query = "SELECT person_id, json_payload, previous_json_payload FROM $api_data_staging_table WHERE submission_status = 'pending' OR submission_status = 'error';"




<#
.SYNOPSIS
Retrieve OAuth 2.0 access token

.DESCRIPTION
send POST request to DfE endpoint using DfE supplied LA/client credentials.
Requires client ID, client secret, scope, and token endpoint to be set in current session scope (as vars).
Returns access token string if success, or $null if auth fails.

.PARAMETER client_id
(Client-level variable) client ID provided for OAuth authentication.

.PARAMETER client_secret
(Client-level variable) client secret used for authentication.

.PARAMETER scope
(Client-level variable) requested scope for token.

.PARAMETER token_endpoint
(Client-level variable) OAuth 2.0 token endpoint URL.

.OUTPUTS
String - bearer token to use in Authorisation header, or $null if request fails.

.EXAMPLE
$accessToken = Get-OAuthToken

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09

#>
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
        Write-Host "❌ Error retrieving OAuth token: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}
# fresh token
$bearer_token = Get-OAuthToken

# did we get a token ok
if (-not $bearer_token) {
    Write-Host "❌ Failed to retrieve OAuth token. Exiting script." -ForegroundColor Red
    exit
}


# Guidance states SupplierKey must be supplied
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $bearer_token"
    "SupplierKey"   = $supplier_key
}




<#
.SYNOPSIS
Executes SQL that does not return result set

.DESCRIPTION
Opens (SQL)Server connection and executes provided SQL command 
suitable for ops UPDATE, INSERT, DELETE, SELECT if not capturing result
Note: SELECT queries will run but results discarded.

.PARAMETER connectionString
(SQL Server) connection string to establish connect

.PARAMETER query
SQL statement to execute. UPDATE, INSERT, DELETE. SELECT allowed but results not returned

.EXAMPLE
Execute-NonQuerySql -connectionString $connStr -query "UPDATE staging_table SET status = 'sent' WHERE person_id = 'abc123'"

.NOTES
Used for db logging, tracking API responses, and updating processing state

Author: D2I/RH
Version: 1.0
Updated: 2025-04-09
#>

function Execute-NonQuerySql {
    param (
        [string]$connectionString,
        [string]$query
    )
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        [void]$cmd.ExecuteNonQuery()
        $conn.Close()
    } catch {
        Write-Host "❌ SQL execution failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}





<#
.SYNOPSIS
Update db with API response metadata on successful submitted records

.DESCRIPTION
Parses list of API response strings (expected containing timestamp and UUID),
extract metadata, and update corresponding records in staging table. Archive current payload and hash

.PARAMETER batch
array of objects, each a submitted record with person_id

.PARAMETER responseItems
array of response strings from API, expected in format: `yyyy-MM-dd_HH:mm:ss.ff_UUID.json`

.PARAMETER connectionString
connection string for db and data source db table access 

.PARAMETER tableName
data source db table (ssd api data staging) also where status and response values updated

.EXAMPLE
Update-ApiResponseForBatch -batch $records -responseItems $apiResponseLines -connectionString $connStr -tableName "staging_table"

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09
#>
function Update-ApiResponseForBatch {
    param (
        [array]$batch,
        [array]$responseItems,
        [string]$connectionString,
        [string]$tableName
    )

    for ($i = 0; $i -lt $batch.Count; $i++) {
        $record = $batch[$i]
        $personId = $record.person_id
        $responseLine = $responseItems[$i]

        if ($responseLine -match '^\s*(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2}\.\d{2})_(.+?)\.json\s*$') {
            $datePart = $matches[1]
            $timePart = $matches[2]
            $uuid = $matches[3]

            $timestampString = "$datePart $timePart"
            try {
                $payloadTimestamp = [DateTime]::ParseExact($timestampString, "yyyy-MM-dd HH:mm:ss.ff", $null)
            } catch {
                Write-Host "⚠️ Could not parse timestamp for item: $responseLine" -ForegroundColor Yellow
                $payloadTimestamp = $null
            }

            $escapedApiResponse = "$uuid" -replace "'", "''"

            $updateQuery = @"
UPDATE $tableName
SET submission_status = 'sent',
    api_response = '$escapedApiResponse', 
    submission_timestamp = '$payloadTimestamp',
    previous_hash = current_hash,
    previous_json_payload = json_payload, 
    row_state = 'unchanged',
    partial_json_payload = NULL  
WHERE person_id = '$personId';
"@
            Execute-NonQuerySql -connectionString $connectionString -query $updateQuery
            Write-Host "✅ Updated record person_id ${personId} with UUID $uuid and timestamp $payloadTimestamp" -ForegroundColor Cyan
        } else {
            Write-Host "⚠️ Unexpected response format for record #${i}: $responseLine" -ForegroundColor Yellow
        }
    }
}



<#
.SYNOPSIS
Log API submission failures to db

.DESCRIPTION
Handle both full and partial batch failures. Use regex to detect fail record indexes in API error,
and update `submission_status` and `api_response` in defined db staging table

.PARAMETER batch
array of original batch records submitted

.PARAMETER connectionString
connection string used to update staging table.

.PARAMETER tableName
table where API errors logged (data staging table)

.PARAMETER errorMessage
shortened/defined description of error stored back on staging table (e.g. "Malformed Payload")

.PARAMETER detailedError
full response or body content returned from API error

.PARAMETER statusCode
HTTP status code received from any failed API request

.EXAMPLE
Handle-BatchFailure -batch $records -connectionString $connStr -tableName "staging_table" -errorMessage "Malformed Payload" -detailedError $apiBody -statusCode 400

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09
#>
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
            $statusMessage = "API error ($statusCode): $errorMessage — $detailedError"
        } else {
            $statusMessage = "API error ($statusCode): $errorMessage — Record valid but batch failed"
        }

        $escapedMessage = $statusMessage -replace "'", "''"

        $updateQuery = @"
UPDATE $tableName
SET submission_status = 'error',
    api_response = '$escapedMessage'
WHERE person_id = '$personId';
"@
        Execute-NonQuerySql -connectionString $connectionString -query $updateQuery
        Write-Host "⚠️ Logged API error for person_id ${personId}: ${statusMessage}" -ForegroundColor Yellow
    }
}




<#
.SYNOPSIS
Log individual API submission failures to db.

.DESCRIPTION
Take array of failure records, each containing `person_id` and `response` string,
and update corresponding db rows with status of 'error' and failure message in `api_response`(body - but header also used for response code)

.PARAMETER failures
array of objects, each with `person_id` and `response` on failed API submission

.PARAMETER connectionString
(SQL)Server connection string for db and data source db table access 

.PARAMETER tableName
data source db table (ssd api data staging) also where status and response values updated

.EXAMPLE
Update-FailedApiResponses -failures $FailedResponses -connectionString $connStr -tableName "api_data_staging"
(or "api_data_staging_anon" if non-live testing

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09
#>
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
        Execute-NonQuerySql -connectionString $connectionString -query $updateQuery

        if ($personId) {
            Write-Host "⚠️ Logged API error for person_id ${personId}: ${escapedResponse}" -ForegroundColor Yellow
        } else {
            Write-Host "⚠️ Logged API error for unknown person_id. Message: ${escapedResponse}" -ForegroundColor Yellow
        }
    }
}




<#
.SYNOPSIS
Submit a batch of JSON records to API and process response

.DESCRIPTION
Handles sending JSON payloads via POST request to a specified API endpoint. 
Implements retry logic on recoverable HTTP status codes, incl. *exponential backoff* for cases 403 (Forbidden), 401 (Unauthorised), and 429 (Rate Limit).
On success, updates database records with UUID and timestamps from the response.
On fail, log errors to db/staging table via `Handle-BatchFailure`.

Retry delay resets between batches to ensure isolated, clean retry behavior per group - to reduce overhead.

.PARAMETER batch
array of records to send, each containing `person_id` and `json` payload field

.PARAMETER endpoint
full API URL including any required route parameters or query string

.PARAMETER headers
hashtable of HTTP headers, including Auth.

.PARAMETER connectionString
(SQL)Server connection string for db and data source db table access 

.PARAMETER tableName
data source db table (ssd api data staging) also where status and response values updated

.PARAMETER FailedResponses
reference to failed responses for further processing

.PARAMETER FinalJsonPayload
serialised JSON array string sent to API

.PARAMETER maxRetries
Max number of retry attempts for transient API failures (default 3).
Exponential backoff is applied between attempts (for *some* response types).

.PARAMETER timeout
Request timeout in seconds (default 30).

.EXAMPLE
Send-ApiBatch -batch $records -endpoint $apiUrl -headers $authHeaders `
              -connectionString $connStr -tableName "api_data_staging" `
              -FailedResponses ([ref]$FailedResponses) -FinalJsonPayload $jsonString

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09

TO DO:
- Add automatic token refresh on 401 responses
- Parameterise retry delays and max backoff cap?
- Implement request logging to file for audit trail

#>


function Send-ApiBatch {
    param (
        [array]$batch,
        [string]$endpoint,
        [hashtable]$headers,
        [string]$connectionString,
        [string]$tableName,
        [ref]$FailedResponses,
        [string]$FinalJsonPayload,
        [int]$maxRetries = 3,
        [int]$timeout = 30 # exponential backoff: 5s -> 10s -> 20s -> 30s (capped)
    )

    $retryCount = 0
    $initialDelay = 5
    $retryDelay = $initialDelay

    while ($retryCount -lt $maxRetries) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $FinalJsonPayload -ContentType "application/json" -TimeoutSec $timeout

            # debug
            #Write-Host "✅ Raw API Response: $response"

            $responseItems = $response -split '\s+'

            if ($responseItems.Count -ne $batch.Count) {
                Write-Host "⚠️ Response count ($($responseItems.Count)) does not match batch count ($($batch.Count)). Skipping updates." -ForegroundColor Yellow
            } else {
                Update-ApiResponseForBatch -batch $batch -responseItems $responseItems -connectionString $connectionString -tableName $tableName
            }

            break

        } catch {
            $httpStatus = if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $_.Exception.Response.StatusCode.Value__
            } else {
                "Unknown"
            }

            #$detailedErrorMessage = ""
            #if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
            #    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            #    $detailedErrorMessage = $reader.ReadToEnd()
            #}

            #  ensure the response stream is read only once, reset stream position before reading(to avoid possible empty stream if already read)
            $detailedErrorMessage = ""
            if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream.CanSeek) { $stream.Position = 0 }
                $reader = [System.IO.StreamReader]::new($stream)
                $detailedErrorMessage = $reader.ReadToEnd()
                $reader.Close()
            }
            # Fallback if no detailed body returned
            if (-not $detailedErrorMessage) {
                $detailedErrorMessage = $_.Exception.Message
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

            Write-Host "❌ API Request Failed with HTTP Status: $httpStatus ($api_response_message)" -ForegroundColor Red
            if ($detailedErrorMessage) {
                Write-Host "🧾 API Error Detail: $detailedErrorMessage" -ForegroundColor DarkGray
            }

            if (-not $retryAllowed) {
                Write-Host "❌ Retry not permitted for this status code. Logging failure." -ForegroundColor Yellow
                Handle-BatchFailure -batch $batch `
                                    -connectionString $connectionString `
                                    -tableName $tableName `
                                    -errorMessage $api_response_message `
                                    -detailedError $detailedErrorMessage `
                                    -statusCode $httpStatus
                break
            } elseif ($retryCount -eq ($maxRetries - 1)) {
                Write-Host "❌ Max retries reached. Logging failure." -ForegroundColor Yellow
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
                    Write-Host "🔁 403 received — applying exponential backoff. Retrying in $retryDelay seconds..." -ForegroundColor Magenta
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





<#
.SYNOPSIS
Retrieves 'pending' JSON records from a (SQL)Server db

.DESCRIPTION
Connects to a (SQL) Server instance using the provided connection string and executes a SQL query to retrieve records.
Each row is expected to contain a `person_id` and a valid JSON string in `json_payload`. Valid records are parsed and returned
as a PowerShell array of custom objects with `person_id` and `json` properties. Skips any rows with empty or invalid JSON.

.PARAMETER connectionString
A valid (SQL)Server connection string for accessing the source database.

.PARAMETER query
The SQL query to execute, typically selecting records with pending status and a non-null `json_payload`.

.RETURNS
An array of PowerShell custom objects. Each object has:
- person_id : A unique identifier for the record.
- json      : The parsed JSON content as a nested object.

.EXAMPLE
$query = "SELECT person_id, json_payload FROM api_data_staging WHERE submission_status = 'pending'"
$records = Get-PendingRecordsFromDb -connectionString $connStr -query $query

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09

TO DO:
- Need to extend 'pending' to also include previously rejected 'error' status records! 
#>
function Get-PendingRecordsFromDb {
    param (
        [string]$connectionString,
        [string]$query
    )

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
            $jsonPayload = $reader["json_payload"]

            ## debug
            #Write-Host "💾 Raw DB Read — person_id: '$personId', Raw JSON: '$jsonPayload'"

            if (-not $jsonPayload -or $jsonPayload.Trim() -eq "") {
                Write-Host "⚠️ Skipping record — person_id '$personId' has NULL or empty json_payload" -ForegroundColor Yellow
                continue
            }

            try {
                $parsedJson = $jsonPayload | ConvertFrom-Json -ErrorAction Stop

                if ($null -eq $parsedJson) {
                    Write-Host "⚠️ Skipping record — person_id '$personId' has unparsable JSON" -ForegroundColor Yellow
                    continue
                }

                $record = [PSCustomObject]@{
                    person_id = $personId
                    json      = $parsedJson
                }

                $JsonArray += $record

            } catch {
                Write-Host "❌ Failed to parse JSON for person_id '$personId': $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        $reader.Close()
        $connection.Close()
    } catch {
        Write-Host "Error connecting to SQL Server: $($_.Exception.Message)" -ForegroundColor Red
    }

    return ,$JsonArray
}







<#
.SYNOPSIS
Converts batch of records into formatted JSON array for API submission

.DESCRIPTION
Take array of objects containing a `json` field and serialise into single compressed JSON array string.
always output a JSON array regardless of number of records (incl. if there is only one) - downstream API expects array payload.

.PARAMETER batch
array of custom objects, each containing `json` property with (structured)data to be serialised

.RETURNS
single JSON string representing batch as compressed JSON array.

.EXAMPLE
$payload = ConvertTo-CorrectJson -batch $records
# Returns: '[{"la_child_id":"abc", ...}, {"la_child_id":"def", ...}]'

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09
#>
function ConvertTo-CorrectJson {
    param (
        [array]$batch
    )

    # Always send array format regardless of size
    $payloadBatch = $batch | ForEach-Object { $_.json }
    return ($payloadBatch | ConvertTo-Json -Depth 10 -Compress)
}



<#
.SYNOPSIS
Returns hard-coded single test record for API tests

.DESCRIPTION
Provides minimal, valid JSON record as PowerShell obj to simulate db record without touching db
Allows additional further/step 2 local testing without relying on db connectivity or data

.RETURNS
array with single custom object, containing `person_id` and corresponding `json` payload

.EXAMPLE
$records = Get-HardcodedTestRecord
# Use this to test downstream batch processing and API submission steps

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09
#>
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
    Write-Host "✅ Keys after parsing test record: $($parsedJson.PSObject.Properties.Name -join ', ')"

    return ,@([PSCustomObject]@{
        person_id = "f96f473f1feb4d6da3379d06670844fd"
        json      = $parsedJson
    })
}





<#
.SYNOPSIS
Convert batch of records into formatted JSON array for API submission

.DESCRIPTION
serialises batch of objects (each with `json` property) into single JSON string
ensures that even if one record, output is valid JSON array by coercing|wrapping 
single object in brackets.

.PARAMETER batch
array of objects, each containing `json` field with data to serialise

.RETURNS
string JSON array, formatted for API transmission

.EXAMPLE
$payload = ConvertTo-CorrectJson -batch $records
Invoke-RestMethod -Uri $api -Method Post -Body $payload -ContentType "application/json"

.NOTES
Author: D2I/RH
Version: 1.0
Created: 2025-04-09
#>
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





# Guidance states SupplierKey must be supplied
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $bearer_token"
    "SupplierKey"   = $supplier_key
}


# connection string
$connectionString = "Server=$server;Database=$database;Integrated Security=True;"



##
## Initial connection test option - send single minimal test record
## This set to $false when ready to pull data direct from DB, otherwise sends hard-coded test record




if ($useTestRecord) {
    $JsonArray = Get-HardcodedTestRecord
    Write-Host "📊 API connection using hardcoded test data..."
} else {
    $sw_db = [System.Diagnostics.Stopwatch]::StartNew()
    $JsonArray = Get-PendingRecordsFromDb -connectionString $connectionString -query $query
    $sw_db.Stop()
    Write-Host "⏱️ Fetch+parse records from DB: $($sw_db.Elapsed.TotalSeconds) seconds"

    Write-Host "📊 API connection using DB staging data table..."
}
Write-Host "📊 Number of records in API payload : $($JsonArray.Count)"
##


if (-not (Get-Command Send-ApiBatch -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Send-ApiBatch not in scope — check function load" -ForegroundColor Red
}




## debug
## confirm person_id record has recognised json associated
#$JsonArray | ForEach-Object {
#    $json = $_.json
#    $hasJson = ($json -ne $null -and $json.PSObject.Properties.Count -gt 0)
#    Write-Host "🔍 Test Input: person_id = '$($_.person_id)', JSON present = $hasJson"
#}


$FailedResponses = New-Object System.Collections.ArrayList # track failed API responses for logging
$totalRecords = $JsonArray.Count # total records available to process
$batchSize = 100 # DfE defined max batch size
$totalBatches = [math]::Ceiling($totalRecords / $batchSize) # num of batches needed


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
            Write-Host "⚠️ Index $i out of range of JsonArray (Count = $($JsonArray.Count)). Skipping." -ForegroundColor Yellow
            continue
        }

        # Get current record (person_id + json payload) for checks
        $record = $JsonArray[$i]
        $pidCheck = $record.person_id
        $jsonCheck = $record.json

        # Check record valid: has requ fields, non-null, and structured as we expect
        $valid = ($record -ne $null -and $record.PSObject.Properties["person_id"] -and $record.PSObject.Properties["json"] -and $pidCheck -ne $null -and $pidCheck -ne "" -and $jsonCheck -ne $null)

        if ($valid) {
            # valid, add it to the current batch slice
            $batchSlice += $record
        } else {
            # record not as expected
            Write-Host "⚠️ Skipping empty or invalid record during batch slice. Person ID: '$pidCheck'" -ForegroundColor Yellow
        }
    }

    ## debug
    ## contents of raw json records pre-send
    #Write-Host "🗪 Raw batch before filtering: $($batchSlice.Count)"
    #foreach ($b in $batchSlice) {
    #    Write-Host "🔍 Raw: person_id = '$($b.person_id)', JSON = '$($b.json)'"
    #}


    Write-Host "🚚 Sending batch $($batchIndex + 1) of $totalBatches..."

    # if a single record exists, we need to physically/coerce wrap it with [ ] before hitting api
    $finalPayload = ConvertTo-CorrectJson -batch $batchSlice


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

    # debug
    $sw_batch = [System.Diagnostics.Stopwatch]::StartNew()

    Send-ApiBatch -batch $batchSlice `
                  -endpoint $api_endpoint_with_lacode `
                  -headers $headers `
                  -connectionString $connectionString `
                  -tableName $api_data_staging_table `
                  -FailedResponses ([ref]$FailedResponses) `
                  -FinalJsonPayload $finalPayload

    # debug
    $sw_batch.Stop()
    Write-Host "📦 Batch $($batchIndex + 1) sent in $($sw_batch.Elapsed.TotalSeconds) seconds"
}

if ($FailedResponses.Count -gt 0) {
    Update-FailedApiResponses -failures $FailedResponses -connectionString $connectionString -tableName $api_data_staging_table
}

