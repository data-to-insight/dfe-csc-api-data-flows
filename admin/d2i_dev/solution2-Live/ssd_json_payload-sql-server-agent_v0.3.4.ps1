
<#

note.... this is the move to partial sends, requires additional partial field on staging table 
ALTER TABLE ssd_api_data_staging
ADD partial_json_payload NVARCHAR(MAX) NULL;



Script Name: SSD API
Description:
    PowerShell script automates extraction of pre-defined JSON payload from SSD (SQL Server), 
    submitting payload to API, updating submission status within $api_data_staging_table in SSD.
    Frequency of data refresh within $api_data_staging_table, execution of this script set by pilot LA,
    not defined/set/automated within this process. 

Key Features:
- Extracts pending JSON payload from specified/pre-populated $api_data_staging_table
- Sends data to defined API endpoint OR simulates process for testing
- Updates submission statuses on SSD $api_data_staging_table: Sent, Error, or Testing as submission history

Parameters:
- $internalTesting: Boolean flag to toggle testing mode. When true, no data sent to API
- $server: SQL Server instance name
- $database: Database name
- $api_data_staging_table: Table containing JSON payloads, status information
- $url: API endpoint
- $token: Authentication token for API

Usage:
- Set $internalTesting to true during testing to simulate API call without sending data to API endpoint
- Update $server, $database to match LA environment

Prerequisites:
- PowerShell 5.1 or later (permissions for execution)
- .net accessible (enable db connection)
- SqlServer PowerShell module installed

- SQL Server with SSD structure deployed Incl. populated api_data_staging_table non-core table


Author: D2I
Version: 0.3.3
Last Updated: 010425
#>


# DEV ONLY: 
$scriptStartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Started: $scriptStartTime ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray

# Test mode flag
$internalTesting = $false # Set $false to (re)enable external API calls
$testOutputFilePath = "C:\Users\RobertHa\Documents\api_payload_test.json"  


# Connection
$server = "ESLLREPORTS04V" 
$database = "HDM_Local"
$api_data_staging_table = "ssd_api_data_staging_anon"  # Note LIVE: ssd_api_data_staging | TESTING : ssd_api_data_staging_anon


# # API Configuration
$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1"
$token_endpoint = 

# # OAuth Credentials
$client_id = 
$client_secret =
$scope = 

# # Subscription Key
$supplier_key = 

# API Endpoint with LA Code
$la_code = 845 
$api_endpoint_with_code = "$api_endpoint/children_social_care_data/$la_code/children"
Write-Host "🔗 Final API Endpoint: $api_endpoint_with_code"


# Temporary local logging (failsafe)
$logFile = "C:\Users\RobertHa\Documents\api_temp_log.json"


#token retrieval
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



function Execute-NonQuerySql {
# execute SQL statements using ADO.NET without SqlServer mod
    param (
        [string]$connectionString,
        [string]$query
    )
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        [void]$cmd.ExecuteNonQuery() # [void] supress returns int (num rows affected) or use $rowsAffected = $cmd.ExecuteNonQuery()
        $conn.Close()
    } catch {
        Write-Host "❌ SQL execution failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}



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
            $record = @{
                person_id = $reader["person_id"]
                json       = $reader["json_payload"] | ConvertFrom-Json
            }
            $JsonArray += $record
        }

        $reader.Close()
        $connection.Close()
    } catch {
        Write-Host "Error connecting to SQL Server: $($_.Exception.Message)" -ForegroundColor Red
    }

    return $JsonArray
}

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

        # expected success response format == 2025-04-02_09:04:19.87_62268a7d-e34f-4de0-8eef-f4c407965147.json
        if ($responseLine -match '^(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2}\.\d{2})_(.+?)\.json$') {

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

            $escapedApiResponse = "$uuid" -replace "'", "''" # populate submission_status with response uuid

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
            Write-Host "✅ Updated record person_id $personId with UUID $uuid and timestamp $payloadTimestamp" -ForegroundColor Cyan
        } else {
            Write-Host "⚠️ Unexpected response format for record #${i}: $responseLine" -ForegroundColor Yellow
        }
    }
}

function Handle-BatchFailure {
    param (
        [array]$batch,
        [string]$connectionString,
        [string]$tableName,
        [string]$errorMessage
    )

    $personIdList = $batch | ForEach-Object { "'$($_.person_id)'" } -join ","
    $updateErrorQuery = @"
UPDATE $tableName
SET submission_status = 'error',
    api_response = 'API error: $errorMessage'
WHERE person_id IN ($personIdList);
"@
    Execute-NonQuerySql -connectionString $connectionString -query $updateErrorQuery
}

function Send-ApiBatch {
    param (
        [array]$batch,
        [string]$endpoint,
        [hashtable]$headers,
        [string]$connectionString,
        [string]$tableName,
        [int]$maxRetries = 3,
        [int]$timeout = 30
    )

    $payloadBatch = $batch | ForEach-Object { $_.json }
    $FinalJsonPayload = $payloadBatch | ConvertTo-Json -Depth 10 -Compress

    $retryCount = 0
    $retryDelay = 5

    while ($retryCount -lt $maxRetries) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $FinalJsonPayload -ContentType "application/json" -TimeoutSec $timeout
            Write-Host "✅ Raw API Response: $response"

            $responseItems = $response -split '\s+'

            if ($responseItems.Count -ne $batch.Count) {
                Write-Host "⚠️ Response count ($($responseItems.Count)) does not match batch count ($($batch.Count)). Skipping updates." -ForegroundColor Yellow
            } else {
                Update-ApiResponseForBatch -batch $batch -responseItems $responseItems -connectionString $connectionString -tableName $tableName
            }

            break  # exit retry

        } catch {
            $retryCount++
            $httpStatus = if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $_.Exception.Response.StatusCode.Value__
            } else {
                "Unknown"
            }

            switch ($httpStatus) {
                204 { $api_response_message = "No content"; $payloadTimestamp = $null }
                400 { $api_response_message = "Malformed Payload"; $payloadTimestamp = $null }
                401 { $api_response_message = "Invalid API token"; $payloadTimestamp = $null }
                403 { $api_response_message = "API access disallowed"; $payloadTimestamp = $null }
                413 { $api_response_message = "Payload exceeds limit"; $payloadTimestamp = $null }
                429 { $api_response_message = "Rate limit exceeded"; $payloadTimestamp = $null }
                default { $api_response_message = "Unexpected Error: $httpStatus"; $payloadTimestamp = $null }
            }

            Write-Host "❌ API Request Failed with HTTP Status: $httpStatus ($api_response_message)" -ForegroundColor Red


            if ($retryCount -eq $maxRetries) {
                Write-Host "❌ Max retries reached. Logging failure." -ForegroundColor Yellow
                Handle-BatchFailure -batch $batch -connectionString $connectionString -tableName $tableName -errorMessage $httpStatus
                throw
            } else {
                Write-Host "Retrying in $retryDelay seconds..."
                Start-Sleep -Seconds $retryDelay
                $retryDelay *= 2
            }
        }
    }
}




$JsonArray = Get-PendingRecordsFromDb -connectionString $connectionString -query $query

if ($JsonArray.Count -eq 0) {
    Write-Host "No pending records found." -ForegroundColor Yellow
    return
}

$totalRecords = $JsonArray.Count
$batchSize = 100 # api defined max batch count
$totalBatches = [math]::Ceiling($totalRecords / $batchSize) # split pending batch sizes

for ($batchIndex = 0; $batchIndex -lt $totalBatches; $batchIndex++) {
    $startIndex = $batchIndex * $batchSize
    $endIndex = [math]::Min($startIndex + $batchSize - 1, $totalRecords - 1)
    $batch = $JsonArray[$startIndex..$endIndex]

    Write-Host "🚚 Sending batch $($batchIndex + 1) of $totalBatches..."
    
    Send-ApiBatch -batch $batch `
                  -endpoint $api_endpoint_with_code `
                  -headers $headers `
                  -connectionString $connectionString `
                  -tableName $api_data_staging_table
}
