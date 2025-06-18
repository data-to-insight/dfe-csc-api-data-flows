

<#
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
Version: 0.2.6
Last Updated: 030225
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
$logData = @{
    "timestamp" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "status" = "sent"
    "response" = $api_response_message
    "previous_hash" = $previousHash
    "previous_json_payload" = $finalJsonPayload
} | ConvertTo-Json -Depth 10


# NOTE TESTING LIMITER 
# Query unsubmitted|pending json payload(s)
if ($testingMode) {
    $query = @"
    SELECT TOP 50 id, json_payload  
    FROM $api_data_staging_table
    WHERE submission_status = 'pending';
"@
} else {
    $query = @"
    SELECT id, json_payload
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



# # GET LA_CODE programmatically
# $la_code_query = @"
# SELECT MAIN_CODE FROM HDM.Education.DIM_LOOKUP_HOME_AUTHORITY 
# WHERE LOOKUP = 'LALocal';
# "@

# try {
#     $la_code_data = Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $la_code_query -TrustServerCertificate
#     if ($la_code_data -ne $null -and $la_code_data.Count -gt 0) {
#         $la_code = $la_code_data.MAIN_CODE
#         Write-Host "Retrieved la_code from database: $la_code"
#     } else {
#         $la_code = "000"  
#         Write-Host "Education module or la_code not available!"
#         Write-Host "User must ensure LA_CODE is hard coded in API script."
#         Write-Host "Using temporary default to avoid API script failure: $la_code"        
#     }
# } catch {
#     Write-Host "Error retrieving la_code: $($_.Exception.Message). Using default: $la_code"
#     $la_code = "000"
# }



# DEBUG
# Select a random record from the dataset
$randomIndex = Get-Random -Minimum 0 -Maximum $data.Count
$jsonArrayDebug = $data[$randomIndex].json_payload | ConvertFrom-Json # Get sample/random record towards visual checks

# DEBUG verification ($testingMode = $true)
Write-Host "`nDebug: Example JSON Payload: `n$jsonArrayDebug" -ForegroundColor Gray # debug 
##



# Raw JSON strings into objects before combining
$jsonArray = $data | ForEach-Object { $_.json_payload | ConvertFrom-Json }

# JSON specification structure incl. la_code + child payload array
$finalJsonPayload = @{
    "la_code" = $la_code
    "Children" = $jsonArray
} | ConvertTo-Json -Depth 10 -Compress





# Retry logic for API call
$maxRetries = 3
$retryDelay = 5
$retryCount = 0
$apiTimeoutSec = 30  

try {
    if (-not $testingMode) {

        # Potentially live data now leaving LA $testingMode=False
        while ($retryCount -lt $maxRetries) {
            try {
                # API call incl. timeout and certificate validation
                $response = Invoke-RestMethod -Uri $api_endpoint_with_code -Method Post -Headers @{
                    Authorization = "Bearer $token"     # auth header
                    ContentType = "application/json"    # expected content
                } -Body $finalJsonPayload -TimeoutSec $apiTimeoutSec -SkipCertificateCheck:$false

                # API response status code
                $responseStatusCode = $response.StatusCode

                # API Response Handling
                switch ($responseStatusCode) {
                    200 { 
                        Write-Host "Success: Data received." -ForegroundColor Green
                        $api_response_message = "Data received"
                    }
                    204 { 
                        Write-Host "No Content: Request accepted but no content returned." -ForegroundColor Yellow
                        $api_response_message = "No content"
                    }
                    400 { 
                        Write-Host "Error: Payload was malformed." -ForegroundColor Red
                        $api_response_message = "Malformed Payload"
                    }
                    401 { 
                        Write-Host "Unauthorised: API token is invalid or missing." -ForegroundColor Yellow
                        $api_response_message = "Invalid API token"
                    }
                    403 { 
                        Write-Host "Forbidden: Access to API is restricted." -ForegroundColor Yellow
                        $api_response_message = "API access disallowed"
                    }
                    413 { 
                        Write-Host "Too Many Records: Payload exceeds size limit." -ForegroundColor Yellow
                        $api_response_message = "Payload exceeds limit"
                    }
                    429 { 
                        Write-Host "Too Many Requests: Rate limit exceeded. Retry later." -ForegroundColor Yellow
                        $api_response_message = "Rate limit exceeded"
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
                        row_state = 'unchanged'
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

                    # Attempt log API error in staging table/db
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

    } else {
        # Localised|Fake API call ($testingMode = $true)
        Write-Host "Testing mode: Simulating API call | No data is being sent externally" -ForegroundColor Yellow
    
        # Validate JSON structure
        try {
            $parsedJson = $finalJsonPayload | ConvertFrom-Json  
            if ($parsedJson.PSObject.Properties.Name -contains "Children" -and $parsedJson.Children -is [array]) {
                $recordCount = $parsedJson.Children.Count

                # DEBUG - Remove icons in deployment
                Write-Host "✅ Payload is a valid JSON structure with $recordCount record(s)." -ForegroundColor Green
            } else {
                Write-Host "❌ Payload format issue: Expected 'Children' array missing or incorrect structure." -ForegroundColor Red
                Write-Host "🔍 Debugging JSON Structure:"
                Write-Host ($finalJsonPayload | ConvertTo-Json -Depth 10)
            }
        } catch {
            Write-Host "❌ Payload failed to parse as valid JSON: $($_.Exception.Message)" -ForegroundColor Red
        }
        
    
        # Output JSON payload to file for #DEBUG|review (requires access to $testOutputFilePath local file location)
        try {
            $finalJsonPayload | Out-File -FilePath $testOutputFilePath -Encoding UTF8
            Write-Host "Payload written to file: $testOutputFilePath" -ForegroundColor Cyan
        } catch {
            Write-Host "Failed to write payload to file: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Update (testing) status in db (states falsified 'sent')
        try {
            $updateQuery = @"
            UPDATE $api_data_staging_table
            SET submission_status = 'sent', 
                api_response = 'simulated api call',
                previous_hash = current_hash,
                previous_json_payload = json_payload 
            WHERE submission_status = 'pending';
"@
            # write-Host "Debug: Query being passed: $updateQuery" -ForegroundColor Gray # debug 

            Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
        } catch {
            Write-Host "Failed to update testing status in database: $($_.Exception.Message)" -ForegroundColor Red
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
