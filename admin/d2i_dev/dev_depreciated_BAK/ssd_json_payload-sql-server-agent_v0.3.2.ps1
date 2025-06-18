

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
$testingMode = $false # Set $false to (re)enable external API calls
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


# DEBUG : show the first and last 5 characters of token 
Write-Host "Debug: API Token is $(($env:API_TOKEN -replace '^(.{5}).+(.{5})$', '$1*****$2'))" -ForegroundColor Cyan


function Get-OAuthToken {
    $body = @{
        client_id     = "fe28c5a9-ea4f-4347-b419-189eb761fa42"
        client_secret = "mR_8Q~G~Wdm2XQ2E8-_hr0fS5FKEns4wHNLtbdw7"  # Or use the secondary key
        scope         = "api://children-in-social-care-data-receiver-test-1-live_6b1907e1-e633-497d-ac74-155ab528bc17/.default"
        grant_type    = "client_credentials"
    }

    try {
        $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/cc0e4d98-b9f9-4d58-821f-973eb69f19b7/oauth2/v2.0/token" `
            -Method Post `
            -Body $body `
            -ContentType "application/x-www-form-urlencoded"

        if ($response.access_token) {
            Write-Host "✅ Successfully retrieved OAuth token." -ForegroundColor Green
            return $response.access_token
        } else {
            Write-Host "❌ Failed to retrieve OAuth token, response was empty." -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "❌ Error retrieving OAuth token: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Get Bearer token
$bearer_token = Get-OAuthToken


$headers = @{
    Authorization  = "Bearer $bearer_token"
    SupplierKey    = $supplier_key
    ContentType    = "application/json"
}


if (-not $bearer_token -or -not $supplier_key) {
    Write-Host "❌ Missing Bearer Token or Supplier Key!" -ForegroundColor Red
    if (-not $bearer_token) {
        Write-Host "❌ Failed to retrieve OAuth token. Exiting script." -ForegroundColor Red
        }
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

# DEBUG: Select a random record from the dataset towards visual checks
$randomIndex = Get-Random -Minimum 0 -Maximum $data.Count
$jsonArrayDebug = $data[$randomIndex].json_payload | ConvertFrom-Json 
Write-Host "`nDebug: Example JSON Payload: `n$jsonArrayDebug" -ForegroundColor Gray 



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

# Toggle for full vs partial JSON payload
$usePartialPayload = $false  # Set to $true for partial JSON, $false for full JSON

# Select payload source dynamically
if ($usePartialPayload) {
    Write-Host "⚠️ Using Partial JSON Payload for API request." -ForegroundColor Yellow
    $payloadToSend = @{"la_code" = $la_code; "Children" = $filteredJsonArray} | ConvertTo-Json -Depth 10 -Compress
} else {
    Write-Host "🔵 Using Full JSON Payload for API request." -ForegroundColor Cyan
    $fullJsonArray = $data | ForEach-Object { $_.json_payload | ConvertFrom-Json }
    $payloadToSend = @{"la_code" = $la_code; "Children" = $fullJsonArray} | ConvertTo-Json -Depth 10 -Compress
}



try {
    if (-not $testingMode) {
        # LIVE API CALL
        while ($retryCount -lt $maxRetries) {
            try {
                # API Call

                # Debugging: Print headers before making request (ensure keys exist)
                Write-Host "🔍 Debugging Headers:"
                $headers | ConvertTo-Json | Write-Host

                # Make API Call
                $response = Invoke-RestMethod -Uri $api_endpoint_with_code -Method Post -Headers $headers -Body $payloadToSend -TimeoutSec $apiTimeoutSec
                

                # Handle API Response
                $responseStatusCode = $response.StatusCode
                switch ($responseStatusCode) {
                    200 { $api_response_message = "Data received" }
                    204 { $api_response_message = "No content" }
                    400 { $api_response_message = "Malformed Payload" }
                    401 { $api_response_message = "Invalid API token" }
                    403 { $api_response_message = "API access disallowed" }
                    413 { $api_response_message = "Payload exceeds limit" }
                    429 { $api_response_message = "Rate limit exceeded" }
                    default { $api_response_message = "Unexpected Error: $responseStatusCode" }
                }

                Write-Host "✅ API Response: $api_response_message" -ForegroundColor Green

                $escapedApiResponse = $api_response_message -replace "'", "''" # escape single quotes in SQL

                # ✅ Update staging table after API success
                try {
                    $updateQuery = @"
                    UPDATE $api_data_staging_table
                    SET submission_status = 'sent',
                        api_response = '$escapedApiResponse',
                        previous_hash = current_hash,
                        previous_json_payload = json_payload, 
                        row_state = 'unchanged',
                        partial_json_payload = NULL,
                        submission_timestamp = GETDATE()  
                    WHERE submission_status = 'pending';
"@
                    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
                    Write-Host "✅ Database updated after API submission." -ForegroundColor Cyan
                } catch {
                    Write-Host "❌ SQL update failed after API call: $($_.Exception.Message)" -ForegroundColor Red
                }

                break  # Exit retry loop

            } catch {
                $retryCount++
                if ($retryCount -eq $maxRetries) {
                    Write-Host "❌ Maximum retries reached. Logging error." -ForegroundColor Yellow
                    try {
                        $updateErrorQuery = @"
                        UPDATE $api_data_staging_table
                        SET submission_status = 'error',
                            api_response = 'api error: $($_.Exception.Message)'
                        WHERE submission_status = 'pending';
"@
                        Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateErrorQuery -TrustServerCertificate
                    } catch {
                        Write-Host "❌ Failed to log API error in database: $($_.Exception.Message)" -ForegroundColor Red
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
        Write-Host "🔶 Testing mode: Simulating API call (No data sent externally)" -ForegroundColor Yellow

        # ✅ Update database fields in testing mode
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
            Write-Host "✅ Testing mode: Simulated API updates stored in database." -ForegroundColor Cyan
        } catch {
            Write-Host "❌ Failed to update testing status in database: $($_.Exception.Message)" -ForegroundColor Red
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
