<#
Script Name: SSD API
Description:
    This PowerShell script automates extraction of a pre-defined JSON payload from the SSD (SQL Server), 
    submitting payload to an API, and updating a submission status within an $api_collection_table in the SSD.
    The frequency of data refresh within $api_collection_table and the execution of this script is set by the pilot LA,
    and is not defined/set/automated within this process. 

Key Features:
- Extracts pending JSON payload from the specified/pre-populated $api_collection_table
- Sends data to a defined API endpoint OR simulates the process for testing
- Updates submission statuses on SSD $dapi_collection_table: Sent, Error, or Testing as submission history

Parameters:
- $testingMode: Boolean flag to toggle testing mode. When true, no data is sent to the API
- $server: SQL Server instance name
- $database: Database name
- $api_collection_table: Table containing the JSON payloads and status information
- $url: API endpoint
- $token: Authentication token for the API

Usage:
- Set $testingMode to true during testing to simulate API call without actually sending data to API endpoint
- Update $server, $database to match LA environment

Prerequisites:
- PowerShell 5.1 or later (and permissions for execution)
- SQL Server with SSD structure deployed
- SqlServer PowerShell module installed

Author: D2I
Version: 0.0.2
Last Updated: 070125
#>

Import-Module SqlServer

# # test flag
$testingMode = $true  # set as $false to (re)enable api calls

# # connection
$server = "ESLLREPORTS04V"
$database = "HDM_Local"
$api_data_staging_table = "ssd_api_data_staging"

# # api 
$api_endpoint = "https://api.uk/endpoint"

# API endpoint with la_code path parameter
$la_code = 887
$api_endpoint_with_code = "$api_endpoint/$la_code"

# # api token setting

# # 1) set in env variable 
# [Environment]::SetEnvironmentVariable("API_TOKEN", "your-auth-token", "User")
$token = $env:API_TOKEN  # token stored in environment var for security

# # collect unsubmitted json payload(s)
$query = @"
SELECT id, json_payload
FROM ssd_api_data_staging
WHERE submission_status = 'Pending';
"@

# # query on windows auth (and trustservercertificate - trusted as internal!)
try {
    $data = Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $query -TrustServerCertificate
} catch {
    Write-Host "error connecting to sql server: $($_.Exception.Message)"
    return
}

# # no data retrieved?
if ($data -eq $null -or $data.Count -eq 0) {
    Write-Host "no payload record with 'pending' status found. Check ssd and/or $api_data_staging_table has been refreshed."
    return
}

# Combine individual JSON objects into a JSON array
$jsonArrayString = @()
foreach ($row in $data) {
    $jsonArrayString += $row.json_payload
}
$jsonArrayString = $jsonArrayString | ConvertTo-Json -Depth 10 -Compress

# retry logic for api call
$maxRetries = 3
$retryDelay = 5
$retryCount = 0

try {
    if (-not $testingMode) {
        while ($retryCount -lt $maxRetries) {
            try {
                # api call with timeout and certificate validation
                $response = Invoke-RestMethod -Uri $api_endpoint_with_code -Method Post -Headers @{
                    Authorization = "Bearer $token" # HTTP specification defined/RFC 7235
                    ContentType = "application/json"
                } -Body $jsonArrayString -TimeoutSec 30 -SkipCertificateCheck:$false

                # log success api response
                $responseJson = $response | ConvertTo-Json -Depth 10 -Compress
                $updateQuery = @"
UPDATE ssd_api_data_staging
SET submission_status = 'Sent',
    api_response = '$responseJson',
    previous_hash = current_hash,
    row_state = 'unchanged'
WHERE submission_status = 'Pending';
"@
                Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
                Write-Host "api call succeeded for all pending records. exiting retry loop."
                break  # stop retry loop as api call and db update succeeded
            } catch {
                # error handling during api call
                $retryCount++
                if ($retryCount -eq $maxRetries) {
                    Write-Host "maximum retries reached. logging error."
                    throw
                } else {
                    Write-Host "retrying in $retryDelay seconds..."
                    Start-Sleep -Seconds $retryDelay
                    $retryDelay *= 2  # exponential backoff
                }
            }
        }
    } else {
        # fake api call (testing)
        Write-Host "testing mode: simulating api call"

        # Validate JSON structure
        try {
            $parsedJson = $jsonArrayString | ConvertFrom-Json  # convert JSON to object for validation
            if ($parsedJson -is [array]) {
                $recordCount = $parsedJson.Count
                Write-Host "payload is a valid JSON array containing $recordCount record(s)."
            } else {
                Write-Host "payload is valid JSON but not an array (unexpected structure)."
            }
        } catch {
            Write-Host "payload failed to parse as valid JSON."
        }


        # Output JSON payload to file for review
        $testOutputFilePath = "C:\Users\RobertHa\Documents\api_payload_test.json"  
        try {
            $jsonArrayString | Out-File -FilePath $testOutputFilePath -Encoding UTF8
            Write-Host "Payload written to file: $testOutputFilePath"
        } catch {
            Write-Host "Failed to write payload to file: $($_.Exception.Message)"
        }

        # Update status to 'Testing'
        $updateQuery = @"
UPDATE ssd_api_data_staging
SET submission_status = 'Testing',
    api_response = 'Simulated API Call'
WHERE submission_status = 'Pending';
"@
        Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
    }
} catch {
    # Capture error detail
    $errorType = $_.Exception.GetType().Name
    $errorMessage = $_.Exception.Message -replace "'", "''"  # escape single quotes for SQL

    Write-Host "error occurred: ${errorMessage} (type: ${errorType})"

    # Log error in the database
    $updateErrorQuery = @"
UPDATE ssd_api_data_staging
SET submission_status = 'Error',
    api_response = 'Unexpected Error: $errorMessage'
WHERE submission_status = 'Pending';
"@
    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateErrorQuery -TrustServerCertificate
}
