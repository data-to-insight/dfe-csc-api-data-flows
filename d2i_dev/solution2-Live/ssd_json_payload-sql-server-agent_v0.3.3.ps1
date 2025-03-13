

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

# Test mode flag
$internalTesting = $true # Set $false to (re)enable external API calls
$testOutputFilePath = "C:\Users\RobertHa\Documents\api_payload_test.json"  


# Connection
$server = "ESLLREPORTS04V"
$database = "HDM_Local"
$api_data_staging_table = "ssd_api_data_staging_anon"  # Note LIVE: ssd_api_data_staging | TESTING : ssd_api_data_staging_anon


# # API Configuration
# $api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1"
$token_endpoint = "https://login.microsoftonline.com/cc0e4d98-b9f9-4d58-821f-973eb69f19b7/oauth2/v2.0/token"

# # OAuth Credentials
$client_id = "fe28c5a9-ea4f-4347-b419-189eb761fa42" 
$client_secret = "mR_8Q~G~Wdm2XQ2E8-_hr0fS5FKEns4wHNLtbdw7" 
$scope = "api://children-in-social-care-data-receiver-test-1-live_6b1907e1-e633-497d-ac74-155ab528bc17/.default"

# # Subscription Key
$supplier_key = "6736ad89172548dcaa3529896892ab3f"

# API Endpoint with LA Code
$la_code = 845 
$api_endpoint_with_code = "$api_endpoint/children_social_care_data/$la_code/children"


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


# Query unsubmitted|pending json payload(s)
if ($internalTesting) {
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

# Define the connection string
$connectionString = "Server=$server;Database=$database;Integrated Security=True;"

# Initialise Array to Store Extracted JSON Records
$JsonArray = @()

# Begin Try-Catch for Error Handling
try {
    # Create SQL Connection
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()

    # Execute Query
    $command = $connection.CreateCommand()
    $command.CommandText = $query
    $reader = $command.ExecuteReader()

    # Process Each Row
    while ($reader.Read()) {
        # Extract the JSON string from the row
        $jsonString = $reader["json_payload"]

        # Append the JSON directly as a string to maintain array structure
        $JsonArray += $jsonString
    }

    # Close SQL Connection
    $reader.Close()
    $connection.Close()
} catch {
    Write-Host "Error connecting to SQL Server: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# No payload data retrieved from db?
if ($JsonArray.Count -eq 0) {
    Write-Host "No payload record with 'pending' status found. Check SSD and/or $api_data_staging_table has been refreshed." -ForegroundColor Yellow
    return
}

# Convert JSON array to properly formatted string (Ensuring correct structure)
$FinalJsonPayload = "[" + ($JsonArray -join ",") + "]"

# Debugging: Print JSON payload before sending
Write-Host "🔍 Debugging Payload:" 
Write-Host $FinalJsonPayload

# Retry logic for API call
$maxRetries = 3
$retryDelay = 5
$retryCount = 0
$apiTimeoutSec = 30  

try {
    if (-not $internalTesting) {
        # LIVE API CALL
        while ($retryCount -lt $maxRetries) {
            try {
                # Debugging: Print headers before making request
                Write-Host "🔍 Debugging Headers:"
                $headers | ConvertTo-Json | Write-Host

                # Make API Call
                $response = Invoke-RestMethod -Uri $api_endpoint_with_code -Method Post -Headers $headers -Body $FinalJsonPayload -ContentType "application/json" -TimeoutSec $apiTimeoutSec

                # Debug raw response
                Write-Host "✅ Raw API Response: $response"

                # Default response message
                $api_response_message = "Data received"

                # Extract timestamp & UUID if response matches expected format
                $responseParts = $response -split "_"

                if ($responseParts.Count -ge 3) {
                    # Extract timestamp
                    $timestampResponseString = $responseParts[0] + " " + $responseParts[1]

                    try {
                        $payloadTimestamp = [DateTime]::ParseExact($timestampResponseString, "yyyy-MM-dd HH:mm:ss", $null)
                    } catch {
                        Write-Host "⚠️ WARNING: Could not parse timestamp format." -ForegroundColor Yellow
                        $payloadTimestamp = $null
                    }

                    # Extract UUID (remove ".json" if present)
                    $uuidPart = $responseParts[2] -replace "\.json$", ""

                    # Append UUID to API response message
                    $api_response_message = "Data received_$uuidPart"

                    # Debugging Output
                    Write-Host "✅ Extracted API Response Timestamp: $payloadTimestamp"
                    Write-Host "✅ Full API Response Message: $api_response_message"
                } else {
                    Write-Host "⚠️ WARNING: Unexpected API response format - unable to extract timestamp and UUID."
                    $payloadTimestamp = $null
                }

                # ✅ Update staging table after API success
                try {
                    # Escape single quotes for SQL storage
                    $escapedApiResponse = $api_response_message -replace "'", "''"

                    $updateQuery = @"
                    UPDATE $api_data_staging_table
                    SET submission_status = 'sent',
                        api_response = '$escapedApiResponse',
                        submission_timestamp = '$payloadTimestamp',
                        previous_hash = current_hash,
                        previous_json_payload = json_payload, 
                        row_state = 'unchanged',
                        partial_json_payload = NULL  
                    WHERE submission_status = 'pending';
"@
                    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
                    Write-Host "✅ Database updated after API submission." -ForegroundColor Cyan
                } catch {
                    Write-Host "❌ SQL update failed after API call: $($_.Exception.Message)" -ForegroundColor Red
                }

                break  # Exit retry loop

            } catch {
                # If an error occurs, capture HTTP status code
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $httpStatus = $_.Exception.Response.StatusCode.Value__
                } else {
                    $httpStatus = "Unknown"
                }

                # Handle different HTTP errors
                switch ($httpStatus) {
                    204 { $api_response_message = "No content"; $payloadTimestamp = $null }
                    400 { $api_response_message = "Malformed Payload"; $payloadTimestamp = $null }
                    401 { $api_response_message = "Invalid API token"; $payloadTimestamp = $null }
                    403 { $api_response_message = "API access disallowed"; $payloadTimestamp = $null }
                    413 { $api_response_message = "Payload exceeds limit"; $payloadTimestamp = $null }
                    429 { $api_response_message = "Rate limit exceeded"; $payloadTimestamp = $null }
                    default { $api_response_message = "Unexpected Error: $httpStatus"; $payloadTimestamp = $null }
                }

                Write-Host "❌ API Request Failed with HTTP Status: $httpStatus"

                # Handle retries if max retries not reached
                $retryCount++
                if ($retryCount -eq $maxRetries) {
                    Write-Host "❌ Maximum retries reached. Logging error." -ForegroundColor Yellow
                    try {
                        $updateErrorQuery = @"
                        UPDATE $api_data_staging_table
                        SET submission_status = 'error',
                            api_response = 'API error: $api_response_message'
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
        }  # End while retry loop
    } else {
        # Simulated API call (Testing Mode)
        Write-Host "🔶 Testing mode: Simulating API call (No data sent externally)" -ForegroundColor Yellow

        # ✅ Update database fields in testing mode
        try {
            $updateQuery = @"
            UPDATE $api_data_staging_table
            SET submission_status = 'simulated sent', 
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
