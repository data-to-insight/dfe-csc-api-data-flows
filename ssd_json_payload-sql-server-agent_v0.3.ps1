

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
- $testingMode: Boolean flag to toggle testing mode. When true, no data sent to API
- $server: SQL Server instance name
- $database: Database name
- $api_data_staging_table: Table containing JSON payloads, status information
- $url: API endpoint
- $token: Authentication token for API

Usage:
- Set $testingMode to true during testing to simulate API call without sending data to API endpoint
- Update $server, $database to match LA environment

Prerequisites:
- PowerShell 5.1 or later (permissions for execution)
- SqlServer PowerShell module installed

- SQL Server with SSD structure deployed Incl. populated api_data_staging_table non-core table


Author: D2I
Version: 0.3
Last Updated: 070225
#>


# DEV ONLY: 
$scriptStartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Started: $scriptStartTime ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray


Import-Module SqlServer

# Test mode flag
$testingMode = $true  # Set $false to (re)enable external API calls
$testOutputFilePath = "C:\Users\RobertHa\Documents\api_payload_test.json"  

# Connection
$server = "ESLLREPORTS04V"
$database = "HDM_Local"
$api_data_staging_table = "ssd_api_data_staging_anon"  # Note LIVE: ssd_api_data_staging | TESTING : ssd_api_data_staging_anon

# API
$api_endpoint = "https://api.uk/endpoint"

# Combined API endpoint la_code path
$la_code = 847 # Important - See also GET LA_CODE block
$api_endpoint_with_code = "$api_endpoint/children_social_care_data/$la_code/children"

# API token setting
$token = $env:API_TOKEN  # token stored in environment var

# Temporary local logging (failsafe)
$logFile = "C:\Users\RobertHa\Documents\api_temp_log.json"

# NOTE TESTING LIMITER 
# Query unsubmitted|pending json payload(s)
if ($testingMode) {
    $query = @"
    SELECT TOP 50 id, json_payload, previous_json_payload  
    FROM $api_data_staging_table
    WHERE submission_status = 'pending';
"@
} else {
    $query = @"
    SELECT id, json_payload, previous_json_payload
    FROM $api_data_staging_table
    WHERE submission_status = 'pending';
"@
}

# Get payload data via above query 
try {
    $data = Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $query -TrustServerCertificate
} catch {
    Write-Host "Error connecting to SQL Server: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# No payload data retrieved?
if ($data -eq $null -or $data.Count -eq 0) {
    Write-Host "No payload record with 'pending' status found. Check SSD and/or $api_data_staging_table has been refreshed." -ForegroundColor Yellow
    return
}

# DEBUG: Select a random record from the dataset
$randomIndex = Get-Random -Minimum 0 -Maximum $data.Count
$jsonArrayDebug = $data[$randomIndex].json_payload | ConvertFrom-Json # Get sample/random record towards visual checks
Write-Host "`nDebug: Example JSON Payload: `n$jsonArrayDebug" -ForegroundColor Gray # debug 

# Process JSON changes: Compare json_payload with previous_json_payload
$filteredJsonArray = @()

foreach ($row in $data) {
    $currentJson = $row.json_payload | ConvertFrom-Json
    $previousJson = if ($row.previous_json_payload) { $row.previous_json_payload | ConvertFrom-Json } else { @{} }

    $changedFields = @{}

    foreach ($key in $currentJson.PSObject.Properties.Name) {
        if ($previousJson.PSObject.Properties.Name -contains $key) {
            if ($currentJson.$key -ne $previousJson.$key) {
                $changedFields[$key] = $currentJson.$key
            }
        } else {
            # New field
            $changedFields[$key] = $currentJson.$key
        }
    }

    # Check for removals (Use purge flag where applicable)
    foreach ($key in $previousJson.PSObject.Properties.Name) {
        if (-not ($currentJson.PSObject.Properties.Name -contains $key)) {
            $changedFields[$key] = "false" # Uses purge flag concept
        }
    }

    # Add filtered changes to list
    if ($changedFields.Count -gt 0) {
        $filteredJsonArray += $changedFields
    }
}

# JSON structure with la_code + filtered child payload array
$partialJsonPayload = @{
    "la_code" = $la_code
    "Children" = $filteredJsonArray
} | ConvertTo-Json -Depth 10 -Compress

# Store partial JSON before sending
try {
    $updatePartialJsonQuery = @"
    UPDATE $api_data_staging_table
    SET partial_json_payload = '$partialJsonPayload'
    WHERE submission_status = 'pending';
"@
    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updatePartialJsonQuery -TrustServerCertificate
    Write-Host "✅ Partial JSON logged before API call."
} catch {
    Write-Host "❌ Failed to store partial JSON payload: $($_.Exception.Message)" -ForegroundColor Red
}

# Retry logic for API call
$maxRetries = 3
$retryDelay = 5
$retryCount = 0
$apiTimeoutSec = 30  

try {
    if (-not $testingMode) {
        while ($retryCount -lt $maxRetries) {
            try {
                # API call incl. timeout and certificate validation
                $response = Invoke-RestMethod -Uri $api_endpoint_with_code -Method Post -Headers @{
                    Authorization = "Bearer $token"     
                    ContentType = "application/json"    
                } -Body $partialJsonPayload -TimeoutSec $apiTimeoutSec -SkipCertificateCheck:$false

                # API response status code
                $responseStatusCode = $response.StatusCode

                # API Response Handling
                switch ($responseStatusCode) {
                    200 { 
                        Write-Host "Success: Data received." -ForegroundColor Green
                        $api_response_message = "Data received"
                    }
                    default { 
                        Write-Host "Unexpected response code: $responseStatusCode" -ForegroundColor Red
                        $api_response_message = "Unexpected Error: $responseStatusCode"
                    }
                }

                # Log API response JSON (#DEBUG)
                $responseJson = $response | ConvertTo-Json -Depth 10 -Compress

                # Write response locally before SQL update (failsafe)
                try {
                    $logData | Out-File -FilePath $logFile -Encoding UTF8
                    Write-Host "API call logged locally at: $logFile" -ForegroundColor Cyan
                } catch {
                    Write-Host "Failed to log API response locally: $($_.Exception.Message)" -ForegroundColor Red
                }

                # Update staging table after API success
                try {
                    $updateQuery = @"
                    UPDATE $api_data_staging_table
                    SET submission_status = 'sent',
                        api_response = '$api_response_message',
                        previous_hash = current_hash,
                        previous_json_payload = json_payload, 
                        row_state = 'unchanged',
                        partial_json_payload = NULL 
                    WHERE submission_status = 'pending';
"@
                    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
                    Write-Host "API call succeeded for all pending records. Exiting retry loop." -ForegroundColor Cyan
                } catch {
                    Write-Host "SQL update failed after successful API call: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "If db connection was lost, check local log: $logFile"
                }

                break
            } catch {
                $retryCount++
                if ($retryCount -eq $maxRetries) {
                    Write-Host "Maximum retries reached. Logging error." -ForegroundColor Yellow
                    try {
                        $updateErrorQuery = @"
                        UPDATE $api_data_staging_table
                        SET submission_status = 'error',
                            api_response = 'api error: $($_.Exception.Message)'
                        WHERE submission_status = 'pending';
"@
                        Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateErrorQuery -TrustServerCertificate
                    } catch {
                        Write-Host "Failed to log API error in database: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    throw
                } else {
                    Write-Host "Retrying in $retryDelay seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $retryDelay
                    $retryDelay *= 2
                }
            }
        }
    }
} catch {
    # Log error
    $errorType = $_.Exception.GetType().Name
    $errorMessage = $_.Exception.Message -replace "'", "''"  

    Write-Host "Error occurred: ${errorMessage} (type: ${errorType})" -ForegroundColor Red

    try {
        $updateErrorQuery = @"
        UPDATE $api_data_staging_table
        SET submission_status = 'error',
            api_response = 'unexpected error: $errorMessage'
        WHERE submission_status = 'pending';
"@
        Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateErrorQuery -TrustServerCertificate
    } catch {
        Write-Host "Failed to log unexpected error in database: $($_.Exception.Message)" -ForegroundColor Red
    }
}
