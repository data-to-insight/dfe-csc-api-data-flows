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
$testingMode = $true  # $false to (re)enable api calls

# # connection
$server = "ESLLREPORTS04V"
$database = "HDM_Local"
$api_collection_table = "ssd_api_data_collection"

# # api 
$api_endpoint = "https://api.uk/endpoint"

# # api token setting

# # 1) set in env variable 
# [Environment]::SetEnvironmentVariable("API_TOKEN", "supplied-auth-token", "User")
$token = $env:API_TOKEN  # token stored in environment var for security

# # 2) if using Windows Credential Manager
# cmdkey /add:"SSD_API" /user:"API" /pass:"supplied-auth-token"
# $token = (Get-StoredCredential -Target "SSD_API").Password


# # collect unsubmitted json payload(s)
$query = @"
SELECT id, json_payload
FROM $api_collection_table
WHERE submission_status = 'Pending' 
"@ # should only be one record at pending

# # query on windows auth (and trustservercertificate)
try {
    $data = Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $query -TrustServerCertificate
} catch {
    Write-Host "error connecting to sql server: $($_.Exception.Message)"
    return
}

# # no data retrieved?
if ($data -eq $null -or $data.Count -eq 0) {
    Write-Host "no payload record with 'pending' status found. Check ssd and/or $api_collection_table has been refreshed."
    return
}

foreach ($row in $data) {
    $id = $row.id
    $json = $row.json_payload

    # retry logic for api call
    $maxRetries = 3
    $retryDelay = 5
    $retryCount = 0

    try {
        if (-not $testingMode) {
            while ($retryCount -lt $maxRetries) {
                try {
                    # api call with timeout and certificate validation
                    $response = Invoke-RestMethod -Uri $api_endpoint -Method Post -Headers @{
                        Authorization = "Bearer $token" # HTTP specification defined/RFC 7235
                        ContentType = "application/json"
                    } -Body $json -TimeoutSec 30 -SkipCertificateCheck:$false

                    # log success api response
                    $responseJson = $response | ConvertTo-Json -Depth 10 -Compress
                    $updateQuery = @"
UPDATE $api_collection_table
SET submission_status = 'Sent',
    api_response = '$responseJson'
WHERE id = $id
"@
                    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
                    Write-Host "api call succeeded for id $id. exiting retry loop."
                    break  # stop retry loop as api call and db update succeeded; no further retries needed for this payload

                } catch {
                    # error handling during api call
                    $retryCount++
                    if ($retryCount -eq $maxRetries) {
                        Write-Host "maximum retries reached for id ${id}. logging error."
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
            Write-Host "testing mode: simulating api call for id $id"
            
            # # comment visual checks out if: 
            # - displaying sensitive data in console output GDPR issue
            # - not required for testing

            # parse and display only the top 3 records from the payload (if JSON is an array)
            try {
                $parsedJson = $json | ConvertFrom-Json  # convert JSON to object for console sampling
                
                if ($parsedJson -is [array]) {
                    # take top n records IF it's an array
                    $sampleRecords = $parsedJson | Select-Object -First 2 # n = 1, 2, ...
                    Write-Host "sample record(s) from payload (top 2):"
                    $sampleRecords | ConvertTo-Json -Depth 2 | Write-Host
                } else {
                    # handle non-array JSON (possible single object payload)
                    Write-Host "payload is not an array. displaying as-is:"
                    Write-Host $json
                }
            } catch {
                # fallback if JSON cannot be parsed
                Write-Host "failed to parse JSON payload. displaying raw payload:"
                Write-Host $json
            } ## end visual checks

            # submission_status to 'testing'
            $updateQuery = @"
UPDATE $api_collection_table
SET submission_status = 'Testing',
    api_response = 'Simulated API Call'
WHERE id = $id
"@
            Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateQuery -TrustServerCertificate
        }
    } catch {
    # capture error detail
    $errorType = $_.Exception.GetType().Name
    $errorMessage = $_.Exception.Message -replace "'", "''"  # escape single quotes for SQL

    Write-Host "error processing id ${id}: ${errorMessage} (type: ${errorType})"

    if ($errorType -eq "WebException") {
        Write-Host "api connectivity issue detected."

        # log api-specific error to db/attempted payload record
        $updateErrorQuery = @"
UPDATE $api_collection_table
SET submission_status = 'Error',
    api_response = 'API Error: $errorMessage'
WHERE id = $id
"@
    } elseif ($errorType -eq "SqlException") {
        Write-Host "database query failed."

        # log sql-specific error to db/attempted payload record
        $updateErrorQuery = @"
UPDATE $api_collection_table
SET submission_status = 'Error',
    api_response = 'SQL Error: $errorMessage'
WHERE id = $id
"@
    } else {
        Write-Host "unexpected error occurred."

        # log generic error to db/attempted payload record
        $updateErrorQuery = @"
UPDATE $api_collection_table
SET submission_status = 'Error',
    api_response = 'Unexpected Error: $errorMessage'
WHERE id = $id
"@
    }

    # execute update query to log error
    Invoke-Sqlcmd -ServerInstance $server -Database $database -Query $updateErrorQuery -TrustServerCertificate
}
}    