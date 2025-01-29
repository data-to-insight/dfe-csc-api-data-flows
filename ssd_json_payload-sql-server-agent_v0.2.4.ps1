<#
Script Name: SSD API
Description:
    PowerShell script automates extraction of pre-defined JSON payload from SSD (SQL Server), 
    submitting payload to API, updating submission status within $api_collection_table in SSD.
    Frequency of data refresh within $api_collection_table, execution of this script set by pilot LA,
    not defined/set/automated within this process. 

Key Features:
- Extracts pending JSON payload from specified/pre-populated $api_collection_table
- Sends data to defined API endpoint OR simulates process for testing
- Updates submission statuses on SSD $api_collection_table: Sent, Error, or Testing as submission history

Parameters:
- $testingMode: Boolean flag to toggle testing mode. When true, no data sent to API
- $server: SQL Server instance name
- $database: Database name
- $api_collection_table: Table containing JSON payloads, status information
- $url: API endpoint
- $token: Authentication token for API

Usage:
- Set $testingMode to true during testing to simulate API call without sending data to API endpoint
- Update $server, $database to match LA environment

Prerequisites:
- PowerShell 5.1 or later (permissions for execution)
- SqlServer PowerShell module installed

- SQL Server with SSD structure deployed Incl. populated ssd_api_data_staging non-core table


Author: D2I
Version: 0.2.4
Last Updated: 290125
#>
Import-Module SqlServer

# # test flag
$testingMode = $true  # set as $false to (re)enable API calls
$testOutputFilePath = "C:\Users\RobertHa\Documents\api_payload_test.json"  

# # connection
$server = "ESLLREPORTS04V"
$database = "HDM_Local"
$api_data_staging_table = "ssd_api_data_staging_anon"  # Note LIVE: ssd_api_data_staging | TESTING : ssd_api_data_staging_anon

# # api 
$api_endpoint = "https://api.uk/endpoint"

# API endpoint combined la_code path
$la_code = 847 # Important - See also GET LA_CODE block
$api_endpoint_with_code = "$api_endpoint/children_social_care_data/$la_code/children"

# # api token setting
$token = $env:API_TOKEN  # token stored in environment var for security

# # collect unsubmitted json payload(s)
if ($testingMode) {
    $query = @"
    SELECT TOP 200 id, json_payload  
    FROM $api_data_staging_table
    WHERE submission_status = 'Pending';
"@
} else {
    $query = @"
    SELECT id, json_payload
    FROM $api_data_staging_table
    WHERE submission_status = 'Pending';
"@
}

# # get payload data via above query 
try {
    $data = Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $query -TrustServerCertificate
} catch {
    Write-Host "Error connecting to SQL Server: $($_.Exception.Message)"
    return
}

# # no payload data retrieved?
if ($data -eq $null -or $data.Count -eq 0) {
    Write-Host "No payload record with 'Pending' status found. Check SSD and/or $api_data_staging_table has been refreshed."
    return
}

# # # GET LA_CODE programmatically
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

# Convert raw JSON strings into objects before combining
$jsonArray = $data | ForEach-Object { $_.json_payload | ConvertFrom-Json }

# JSON with la_code + child payload array
$finalJsonPayload = @{
    "la_code" = $la_code
    "Children" = $jsonArray
} | ConvertTo-Json -Depth 10 -Compress

# Debugging output for verification (Testing Mode)
Write-Host "Final JSON Payload: $finalJsonPayload"

# Retry logic for API call
$maxRetries = 3
$retryDelay = 5
$retryCount = 0
$apiTimeoutSec = 30  

try {
    if (-not $testingMode) {
        while ($retryCount -lt $maxRetries) {
            try {
                # API call with timeout and certificate validation
                $response = Invoke-RestMethod -Uri $api_endpoint_with_code -Method Post -Headers @{
                    Authorization = "Bearer $token"     # auth header
                    ContentType = "application/json"    # expected content
                } -Body $finalJsonPayload -TimeoutSec $apiTimeoutSec -SkipCertificateCheck:$false

                # **Extract API response status code**
                $responseStatusCode = $response.StatusCode

                # **New: Enhanced API Response Handling**
                switch ($responseStatusCode) {
                    200 { 
                        Write-Host "Success: Data received."
                        $api_response_message = "Data received"
                    }
                    204 { 
                        Write-Host "No Content: Request accepted but no content returned."
                        $api_response_message = "No content"
                    }
                    400 { 
                        Write-Host "Error: Payload was malformed."
                        $api_response_message = "Malformed Payload"
                    }
                    401 { 
                        Write-Host "Unauthorized: API token is invalid or missing."
                        $api_response_message = "Unauthorized Access"
                    }
                    403 { 
                        Write-Host "Forbidden: Access to API is restricted."
                        $api_response_message = "Forbidden Access"
                    }
                    413 { 
                        Write-Host "Too Many Records: Payload exceeds size limit."
                        $api_response_message = "Too many records"
                    }
                    429 { 
                        Write-Host "Too Many Requests: Rate limit exceeded. Retry later."
                        $api_response_message = "Too many requests"
                    }
                    default { 
                        Write-Host "Unexpected response code: $responseStatusCode"
                        $api_response_message = "Unexpected Error: $responseStatusCode"
                    }
                }

                # Log API response JSON (for debugging)
                $responseJson = $response | ConvertTo-Json -Depth 10 -Compress

                # **Update staging table after API success**
                try {
                    $updateQuery = @"
                    UPDATE $api_data_staging_table
                    SET submission_status = 'Sent',
                        api_response = '$api_response_message',
                        previous_hash = current_hash,
                        row_state = 'unchanged'
                    WHERE submission_status = 'Pending';
"@
                    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
                    Write-Host "API call succeeded for all pending records. Exiting retry loop."
                } catch {
                    Write-Host "SQL update failed after successful API call: $($_.Exception.Message)"
                }

                break
            } catch {
                $retryCount++
                if ($retryCount -eq $maxRetries) {
                    Write-Host "Maximum retries reached. Logging error."

                    # Try to log API error in DB
                    try {
                        $updateErrorQuery = @"
                        UPDATE $api_data_staging_table
                        SET submission_status = 'Error',
                            api_response = 'API Error: $($_.Exception.Message)'
                        WHERE submission_status = 'Pending';
"@
                        Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateErrorQuery -TrustServerCertificate
                    } catch {
                        Write-Host "Failed to log API error in database: $($_.Exception.Message)"
                    }

                    throw
                } else {
                    Write-Host "Retrying in $retryDelay seconds..."
                    Start-Sleep -Seconds $retryDelay
                    $retryDelay *= 2
                }
            }
        }

    } else {
        # Fake API call (Testing Mode)
        Write-Host "Testing mode: Simulating API call"
    
        # Validate JSON structure
        try {
            $parsedJson = $finalJsonPayload | ConvertFrom-Json  
            if ($parsedJson.PSObject.Properties.Name -contains "Children" -and $parsedJson.Children -is [array]) {
                $recordCount = $parsedJson.Children.Count
                # DEBUG - Remove icons for deployment
                Write-Host "✅ Payload is a valid JSON structure with $recordCount record(s)."
            } else {
                Write-Host "❌ Payload format issue: Expected 'Children' array missing or incorrect structure."
                Write-Host "🔍 Debugging JSON Structure:"
                Write-Host ($finalJsonPayload | ConvertTo-Json -Depth 10)
            }
        } catch {
            Write-Host "❌ Payload failed to parse as valid JSON: $($_.Exception.Message)"
        }
        
    
        # Output JSON payload to file for debug|review (requires access to $testOutputFilePath file location)
        try {
            $finalJsonPayload | Out-File -FilePath $testOutputFilePath -Encoding UTF8
            Write-Host "Payload written to file: $testOutputFilePath"
        } catch {
            Write-Host "Failed to write payload to file: $($_.Exception.Message)"
        }

        # Update testing status in DB
        try {
            $updateQuery = @"
            UPDATE $api_data_staging_table
            SET submission_status = 'Testing',
                api_response = 'Simulated API Call'
            WHERE submission_status = 'Pending';
"@
            Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
        } catch {
            Write-Host "Failed to update testing status in database: $($_.Exception.Message)"
        }
    }
} catch {
    # Capture and Log Error
    $errorType = $_.Exception.GetType().Name
    $errorMessage = $_.Exception.Message -replace "'", "''"  

    Write-Host "Error occurred: ${errorMessage} (type: ${errorType})"

    try {
        $updateErrorQuery = @"
        UPDATE $api_data_staging_table
        SET submission_status = 'Error',
            api_response = 'Unexpected Error: $errorMessage'
        WHERE submission_status = 'Pending';
"@
        Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateErrorQuery -TrustServerCertificate
    } catch {
        Write-Host "Failed to log unexpected error in database: $($_.Exception.Message)"
    }
}
