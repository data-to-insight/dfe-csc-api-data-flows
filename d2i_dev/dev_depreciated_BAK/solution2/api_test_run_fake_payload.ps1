
# Endpoint
$la_code = 845 
$base_url = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1/children_social_care_data"
$api_endpoint_with_code = "$base_url/$la_code/children"


#token retrieval
function Get-OAuthToken {
    $token_endpoint = "https://login.microsoftonline.com/cc0e4d98-b9f9-4d58-821f-973eb69f19b7/oauth2/v2.0/token"

    $body = @{
        client_id     = "fe28c5a9-ea4f-4347-b419-189eb761fa42"  
        client_secret = "mR_8Q~G~Wdm2XQ2E8-_hr0fS5FKEns4wHNLtbdw7"  
        scope         = "api://children-in-social-care-data-receiver-test-1-live_6b1907e1-e633-497d-ac74-155ab528bc17/.default" 
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


# Debug
Write-Host "🔍 Debugging Bearer Token: $bearer_token"



# Guidance states SupplierKey must be supplied
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $bearer_token"
    "SupplierKey"   = "6736ad89172548dcaa3529896892ab3f"
}


# Debug
Write-Host "🔍 Debugging Headers:"
Write-Host ($headers | ConvertTo-Json)



# JSON payload - test|fake
$debugJsonPayload = [ordered]@{
  # "la_code" = 845 # removed as not in schema
  #"Children" = @( # removed as children not in schema
    #[ordered]@{
      "la_child_id" = "654321"
      "mis_child_id" = "MIS654321"
      "purge" = $false # parse boolean
      "child_details" = [ordered]@{
        "unique_pupil_number" = "A065432179012" # corrected length
        "former_unique_pupil_number" = "B065432189012" # corrected length
        "unique_pupil_number_unknown_reason" = "UN1"
        "first_name" = "John"
        "surname" = "Doe"
        "date_of_birth" = "2010-06-15"
        "expected_date_of_birth" = "2010-06-15"
        "sex" = "M"
        "ethnicity" = "WBRI"
        "disabilities" = @("HAND", "VIS")
        "postcode" = "AB12 3DE"
        "uasc_flag" = $true
        "uasc_end_date" = "2022-06-14"
        "purge" = $false # parse boolean
      }
      "health_and_wellbeing" = [ordered]@{
        "sdq_assessments" = @(
          [ordered]@{
            "date" = "2022-06-14"
            "score" = 20
          }
        )
        "purge" = $false # parse boolean
      }
      "education_health_care_plans" = @(
        [ordered]@{
          "education_health_care_plan_id" = "EHCP123"
          "request_received_date" = "2022-06-14"
          "request_outcome_date" = "2022-06-20"
          "assessment_outcome_date" = "2022-07-01"
          "plan_start_date" = "2022-08-01"
          "purge" = $false # parse boolean
        }
      )
      "social_care_episodes" = @(
        [ordered]@{
          "social_care_episode_id" = "SC123456"
          "referral_date" = "2022-06-14"
          "referral_source" = "1C"
          "referral_no_further_action_flag" = $false # parse boolean
          "closure_date" = "2022-09-30"
          "closure_reason" = "RC7"
          "care_worker_details" = @(
            [ordered]@{
              "worker_id" = "CW123"
              "start_date" = "2022-06-14"
              "end_date" = "2022-12-14"
            }
          )
          "child_and_family_assessments" = @(
            [ordered]@{
              "child_and_family_assessment_id" = "CFA123"
              "start_date" = "2022-06-14"
              "authorisation_date" = "2022-06-21"
              "factors" = @("1C", "4A")
              "purge" = $false # parse boolean
            }
          )
          "child_in_need_plans" = @(
            [ordered]@{
              "child_in_need_plan_id" = "CINP123"
              "start_date" = "2022-06-14"
              "end_date" = "2022-12-14"
              "purge" = $false # parse boolean
            }
          )
          "section_47_assessments" = @(
            [ordered]@{
              "section_47_assessment_id" = "S47A123"
              "start_date" = "2022-06-14"
              "icpc_required_flag" = $true
              "icpc_date" = "2022-06-30"
              "end_date" = "2022-07-10"
              "purge" = $false # parse boolean
            }
          )
          "child_protection_plans" = @(
            [ordered]@{
              "child_protection_plan_id" = "CPP123"
              "start_date" = "2022-06-14"
              "end_date" = "2022-09-14"
              "purge" = $false # parse boolean
            }
          )
          "child_looked_after_placements" = @(
            [ordered]@{
              "child_looked_after_placement_id" = "CLAP123"
              "start_date" = "2022-06-14"
              "start_reason" = "S"
              "placement_type" = "K1"
              "postcode" = "AB12 3DE"
              "end_date" = "2022-12-14"
              "end_reason" = "E3"
              "change_reason" = "CHILD"
              "purge" = $false # parse boolean
            }
          )
          "adoption" = [ordered]@{
            "initial_decision_date" = "2022-06-14"
            "matched_date" = "2022-09-14"
            "placed_date" = "2022-12-14"
            "purge" = $false # parse boolean
          }
          "care_leavers" = [ordered]@{
            "contact_date" = "2022-12-14"
            "activity" = "F2"
            "accommodation" = "D"
            "purge" = $false # parse boolean
          }
          "purge" = $false # parse boolean
    #    } # removed from upper children
#      )
    }
  )
}

# JSON to formatted str
$debugJsonPayload = $debugJsonPayload | ConvertTo-Json -Depth 10 -Compress

# Rem hidden CRLF chars
$debugJsonPayload = $debugJsonPayload -replace "`r`n", "" -replace "`n", "" -replace "`r", ""

# Debug
Write-Host "Debug Final JSON Payload:"
Write-Host $debugJsonPayload




# API request
try {
    $response = Invoke-RestMethod -Uri $api_endpoint_with_code -Method Post -Headers $headers -Body [$debugJsonPayload] # Add in [] as JsonArray expected
    Write-Host "API Response:"
    Write-Host $response

    # Extract the timestamp (first part before the second underscore)
    $timestampString = $response -split "_" | Select-Object -First 2 -Join " "

    # Convert to DateTime object
    $timestamp = [DateTime]::ParseExact($timestampString, "yyyy-MM-dd HH:mm:ss", $null)

    # Output result
    Write-Host "Extracted Timestamp: $timestamp"



}catch {
    Write-Host "❌ API request failed: $($_.Exception.Message)" -ForegroundColor Red

    # Try to extract the response body from the exception
    if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
        $streamReader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        $errorResponse = $streamReader.ReadToEnd()
        Write-Host "🔴 Error Response Body:`n$errorResponse" -ForegroundColor Red
    } else {
        Write-Host "⚠️ No response body available."
    }

    # Debugging information
    Write-Host "Hitting endpoint: $api_endpoint_with_code" -ForegroundColor Yellow
}