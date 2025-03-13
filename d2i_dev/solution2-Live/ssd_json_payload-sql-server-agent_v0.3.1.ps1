

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
Version: 0.3.2
Last Updated: 070325
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


# API Configuration
$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1"
$token_endpoint = "https://login.microsoftonline.com/cc0e4d98-b9f9-4d58-821f-973eb69f19b7/oauth2/v2.0/token"

# OAuth Credentials
$client_id = "fe28c5a9-ea4f-4347-b419-189eb761fa42"
$client_secret = "mR_8Q~G~Wdm2XQ2E8-_hr0fS5FKEns4wHNLtbdw7"
$scope = "api://children-in-social-care-data-receiver-test-1-live_6b1907e1-e633-497d-ac74-155ab528bc17/.default"

# Subscription Key
$supplier_key = "6736ad89172548dcaa3529896892ab3f"

# API Endpoint with LA Code
$la_code = 845 
$api_endpoint_with_code = "$api_endpoint/children_social_care_data/$la_code/children"


# API token setting
$token = $env:API_TOKEN  # token stored in environment var

# Temporary local logging (failsafe)
$logFile = "C:\Users\RobertHa\Documents\api_temp_log.json"



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

# Get the Bearer token
$bearer_token = Get-OAuthToken
if (-not $bearer_token) {
    Write-Host "Failed to retrieve OAuth token. Exiting script." -ForegroundColor Red
    exit
}



# NOTE TESTING LIMITER 
# Query unsubmitted|pending json payload(s)
if ($testingMode) {
    $query = @"
    SELECT TOP 10 id, json_payload, previous_json_payload  
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
    Write-Host "Partial JSON logged before API call."
} catch {
    Write-Host "Failed to store partial JSON payload: $($_.Exception.Message)" -ForegroundColor Red
}

# Retry logic for API call
$maxRetries = 3
$retryDelay = 5
$retryCount = 0
$apiTimeoutSec = 30  

try {
    if (-not $testingMode) {
        
        # Retrieve OAuth Token
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

        # Get the Bearer token
        $bearer_token = Get-OAuthToken
        if (-not $bearer_token) {
            Write-Host "❌ Failed to retrieve OAuth token. Exiting script." -ForegroundColor Red
            exit
        }

        # Set API headers including OAuth Token & Supplier Key
        $headers = @{
            Authorization  = "Bearer $bearer_token"  # OAuth Bearer token
            SupplierKey    = $supplier_key           # Subscription Key
            ContentType    = "application/json"
        }

        while ($retryCount -lt $maxRetries) {
            try {
                # API call incl. timeout and certificate validation
                $response = Invoke-RestMethod -Uri $api_endpoint_with_code -Method Post -Headers $headers -Body $partialJsonPayload -TimeoutSec $apiTimeoutSec -SkipCertificateCheck:$false

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
                        Write-Host "Unauthorized: API token is invalid or missing." -ForegroundColor Yellow
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
                    $logData = @{
                        "timestamp" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        "status" = "sent"
                        "response" = $api_response_message
                        "previous_hash" = $previousHash
                        "previous_json_payload" = $partialJsonPayload
                    } | ConvertTo-Json -Depth 10
                    $logData | Out-File -FilePath $logFile -Encoding UTF8
                    Write-Host "API call logged locally at: $logFile" -ForegroundColor Cyan
                } catch {
                    Write-Host "Failed to log API response locally: $($_.Exception.Message)" -ForegroundColor Red
                }

                # ✅ Update staging table after API success
                try {
                    $updateQuery = @"
                    UPDATE $api_data_staging_table
                    SET submission_status = 'sent',
                        api_response = '$api_response_message',
                        previous_hash = current_hash,
                        previous_json_payload = json_payload, 
                        row_state = 'unchanged',
                        partial_json_payload = NULL,
                        submission_timestamp = GETDATE()  
                    WHERE submission_status = 'pending';
"@
                    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
                    Write-Host "API call succeeded for all pending records. Exiting retry loop." -ForegroundColor Cyan
                } catch {
                    Write-Host "SQL update failed after successful API call: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "If db connection was lost, check local log: $logFile"
                }

                break  # Exit retry loop after success

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
    } else {
        # Localised|Fake API call ($testingMode = $true)
        Write-Host "Testing mode: Simulating API call | No data is being sent externally" -ForegroundColor Yellow

        # ✅ Update database fields even in testing mode
        try {
            $updateQuery = @"
            UPDATE $api_data_staging_table
            SET submission_status = 'sent', 
                api_response = 'simulated api call',
                previous_hash = current_hash,
                row_state = 'unchanged',   
                previous_json_payload = json_payload,
                submission_timestamp = GETDATE()  
            WHERE submission_status = 'pending';
"@
            Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
            Write-Host "Testing mode: Simulated API call updates stored in database." -ForegroundColor Cyan
        } catch {
            Write-Host "Failed to update testing status in database: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} catch {
    # Log error
    $errorType = $_.Exception.GetType().Name
    $errorMessage = $_.Exception.Message -replace "'", "''"  

    Write-Host "❌ Error occurred: ${errorMessage} (type: ${errorType})" -ForegroundColor Red

    try {
        $updateErrorQuery = @"
        UPDATE $api_data_staging_table
        SET submission_status = 'error',
            api_response = 'unexpected error: $errorMessage'
        WHERE submission_status = 'pending';
"@
        Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateErrorQuery -TrustServerCertificate
    } catch {
        Write-Host "❌ Failed to log unexpected error in database: $($_.Exception.Message)" -ForegroundColor Red
    }
}

