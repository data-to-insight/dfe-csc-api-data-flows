<#
.SYNOPSIS
  CSC API, AAD v2 client credentials, token and POST sender
.DESCRIPTION
  Single token call, v2 only. Posts selectable fake payload to CSC endpoint.
  Plug your LA values, supplied by DfE in the Config block
  Prints AAD errors when token fails, plus basic connectivity diagnostics.
.NOTES
  Author, D2I
  Version, 0.1.3  PS 5.1 compatible (no ternary)
  Date, 27/09/2025
#>
$VERSION = '0.2.0'
Write-Host ("CSC API staging build: v{0}" -f $VERSION)



# ----------- LA Config START -----------
# REQUIRED, replace the details in quotes below with your LA's credentials as supplied by DfE
# from https://pp-find-and-use-an-api.education.gov.uk/ (once logged in)

$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1" # 'Base URL' - Shouldn't need to change


# From the 'Native OAuth Application-flow' block
$client_id       = "OAUTH_CLIENT_ID_CODE" # 'OAuth Client ID'
$client_secret   = "NATIVE_OAUTH_PRIMARY_KEY_CODE"  # 'Native OAuth Application-flow' - 'Primary key' or 'Secondary key'
$scope           = "OAUTH_SCOPE_LINK" # 'OAuth Scope'
$token_endpoint = "OAUTH_TOKEN_ENDPOINT" # From the 'Native OAuth Application-flow' block - 'OAuth token endpoint'

# From the 'subscription key' block
$supplier_key    = "SUBSCRIPTION_PRIMARY_KEY_CODE" # From the 'subscription key' block - 'Primary key' or 'Secondary key'


$la_code         = "000" # Change to your 3 digit LA code

# ----------- LA Config END -----------



#TLS and proxy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::Expect100Continue = $false
try { [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials } catch {}



# Test|Dev switches
$SEND_BODY_MODE     = 'full'     # empty, min, full
$TOKEN_PROBE_ONLY   = $false     # set $true to test getting OAuth token only
$timeoutSec         = 60




# ----------- Config OVERIDE -----------
# D2I Overide block

# ----------- Config OVERIDE END -----------



# Payload selector, empty, min, full
if (-not $SEND_BODY_MODE) { $SEND_BODY_MODE = 'min' }
$timeoutSec = 60

# Optional, run token probe only, set to $true to isolate token issues
if (-not $TOKEN_PROBE_ONLY) { $TOKEN_PROBE_ONLY = $false }

# Diagnostics
$ENABLE_DIAGNOSTICS = $true
$DIAG_ON_HTTP_CODES = @(401,403,407,408,413,415,429,500,502,503,504)
$DIAG_HTTP_PROBE    = $true
$DIAG_PRINT         = $false
$DIAG_CAPTURE       = $true
$script:DiagData    = $null
#endregion


function Describe-Code([int]$c) {
  switch ($c) {
    204 { "No content" }
    400 { "Malformed payload, 400 BadRequest" }
    401 { "Invalid token, 401 Unauthorised" }
    403 { "Forbidden, access disallowed, 403" }
    405 { "Method not allowed, 405" }
    408 { "Request timeout, 408" }
    413 { "Payload too large, 413" }
    415 { "Unsupported media type, 415" }
    429 { "Rate limited, 429" }
    500 { "Internal server error, 500" }
    502 { "Bad gateway, 502" }
    503 { "Service unavailable, 503" }
    504 { "Gateway timeout, 504" }
    default { try { ([System.Net.HttpStatusCode]$c).ToString() } catch { "Other or unexpected, $c" } }
  }
}

function Describe-WebExceptionStatus($status) {
  switch ($status) {
    'NameResolutionFailure'      { 'DNS resolution failed' }
    'ConnectFailure'             { 'TCP connect failed, firewall or blocked port' }
    'ConnectionClosed'           { 'Connection closed prematurely' }
    'ReceiveFailure'             { 'Receive failed, proxy or inspection likely' }
    'SendFailure'                { 'Send failed, MTU or inspection likely' }
    'Timeout'                    { 'Connection or request timed out' }
    'TrustFailure'               { 'Certificate trust failed' }
    'SecureChannelFailure'       { 'TLS handshake failed' }
    'ProxyNameResolutionFailure' { 'Proxy DNS failed' }
    'ProxyAuthenticationRequired'{ 'Proxy requires authentication, 407' }
    default { [string]$status }
  }
}

function Get-ConnectivityDiagnostics {
  param([Parameter(Mandatory=$true)][string]$Url)
  $info = [ordered]@{
    Ran            = $true
    Dns            = $null
    Tcp            = $null
    TlsProtocol    = $null
    TlsCert        = $null
    TlsIssuer      = $null
    TlsPolicyErrors= $null
    HeadRoot       = $null
    HeadPath       = $null
    Note           = $null
  }
  try { $uri = [uri]$Url } catch { $info.Note="bad url"; return [pscustomobject]$info }
  $targetHost = $uri.Host
  $targetPort = if ($uri.IsDefaultPort) { if ($uri.Scheme -eq 'https') { 443 } else { 80 } } else { $uri.Port }

  # DNS
  try {
    $ips = @()
    try { $ips = (Resolve-DnsName -Name $targetHost -Type A -ErrorAction Stop).IPAddress } catch { $ips = [System.Net.Dns]::GetHostAddresses($targetHost) | ForEach-Object { $_.IPAddressToString } }
    $info.Dns = ("{0} -> {1}" -f $targetHost, (($ips | Select-Object -Unique) -join ", "))
  } catch { $info.Dns = "FAILED, " + $_.Exception.Message }

  # TCP and TLS
  try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect($targetHost,$targetPort,$null,$null)
    if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { $tcp.Close(); throw "TCP connect timeout" }
    $tcp.EndConnect($iar)
    $info.Tcp = ("Connected to {0}:{1}" -f $targetHost,$targetPort)
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(),$false,{ param($s,$cert,$chain,$errors) $script:__sslErrors=$errors; $true })
    $script:__sslErrors = [System.Net.Security.SslPolicyErrors]::None
    $ssl.AuthenticateAsClient($targetHost)
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
    $info.TlsProtocol=$ssl.SslProtocol
    $info.TlsCert=$cert.Subject
    $info.TlsIssuer=$cert.Issuer
    $info.TlsPolicyErrors=$script:__sslErrors
    $ssl.Close(); $tcp.Close()
  } catch { $info.Note = "TLS fail, " + $_.Exception.Message }

  if ($DIAG_HTTP_PROBE) {
    try {
      $rootUrl = "{0}://{1}/" -f $uri.Scheme,$uri.Host
      $rootResp = Invoke-WebRequest -Uri $rootUrl -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
      $info.HeadRoot = ("{0} -> {1}" -f $rootUrl,$rootResp.StatusCode)
    } catch { $info.HeadRoot = ("{0} FAILED, {1}" -f $rootUrl,$_.Exception.Message) }
    try {
      $pathResp = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
      $info.HeadPath = ("{0} -> {1}" -f $Url,$pathResp.StatusCode)
    } catch { $info.HeadPath = ("{0} FAILED, {1}" -f $Url,$_.Exception.Message) }
  }
  return [pscustomobject]$info
}

function Get-OAuthToken {
  # v2 client credentials only, requires .default scope
  if (-not $scope -or $scope -notmatch '\.default$') {
    Write-Host "Scope must be api://<resource-app-id>/.default" -ForegroundColor Yellow
    return $null
  }
  $client_id      = $client_id.Trim()
  $client_secret  = $client_secret.Trim()
  $scope          = $scope.Trim()
  $token_endpoint = $token_endpoint.Trim()

  $body = @{
    client_id     = $client_id
    client_secret = $client_secret
    scope         = $scope
    grant_type    = 'client_credentials'
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $response = Invoke-RestMethod -Uri $token_endpoint -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    $sw.Stop()
    Write-Host ("Token fetched in {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    return $response.access_token
  } catch {
    $sw.Stop()
    Write-Host ("Token request failed after {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    if ($_.Exception.Response) {
      try {
        $sr  = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
        $raw = $sr.ReadToEnd()
        if ($raw) {
          try {
            $j = $raw | ConvertFrom-Json
            $errParts = @()
            if ($j.error)            { $errParts += $j.error }
            if ($j.error_description){ $errParts += $j.error_description }
            if ($j.correlation_id)   { $errParts += $j.correlation_id }
            if ($j.error_codes)      { $errParts += ($j.error_codes -join ', ') }
            if ($errParts.Count -gt 0) { Write-Host ("AAD error, {0}" -f ($errParts -join ' | ')) } else { Write-Host $raw }
          } catch { Write-Host $raw }
        }
      } catch {}
    } else {
      Write-Host $_.Exception.Message
    }
    return $null
  }
}

function Token-Probe {
  # direct probe, same vals, print raw body for clarity
  $sc = $scope.Trim()
  if ($sc -notmatch '\.default$') { $sc = "$sc/.default" }

  $probe = @{
    client_id     = $client_id.Trim()
    client_secret = $client_secret.Trim()
    scope         = $sc
    grant_type    = 'client_credentials'
  }
  try {
    $r = Invoke-RestMethod -Uri $token_endpoint.Trim() -Method Post -Body $probe -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    Write-Host "Token OK, length, $($r.access_token.Length)"
    return $true
  } catch {
    Write-Host "Token probe failed"
    if ($_.Exception.Response) {
      $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
      Write-Host ($sr.ReadToEnd())
    } else {
      Write-Host $_.Exception.Message
    }
    return $false
  }
}

# Sample payloads - from DfE 0.8.0 spec
$payload_empty = "[]"

$payload_min = @'
[
  {
    "la_child_id": "Child1234",
    "mis_child_id": "Supplier-Child-1234",
    "child_details": {
      "unique_pupil_number": "ABC0123456789",
      "former_unique_pupil_number": "DEF0123456789",
      "unique_pupil_number_unknown_reason": "UN1",
      "first_name": "John",
      "surname": "Doe",
      "date_of_birth": "2022-06-14",
      "expected_date_of_birth": "2022-06-14",
      "sex": "M",
      "ethnicity": "WBRI",
      "disabilities": ["HAND", "VIS"],
      "postcode": "AB12 3DE",
      "uasc_flag": true,
      "uasc_end_date": "2022-06-14",
      "purge": false
    },
    "purge": false
  }
]
'@

$payload_full = @'
[
  {
    "la_child_id": "Child1234",
    "mis_child_id": "Supplier-Child-1234",
    "child_details": {
      "unique_pupil_number": "ABC0123456789",
      "former_unique_pupil_number": "DEF0123456789",
      "unique_pupil_number_unknown_reason": "UN1",
      "first_name": "John",
      "surname": "Doe",
      "date_of_birth": "2022-06-14",
      "expected_date_of_birth": "2022-06-14",
      "sex": "M",
      "ethnicity": "WBRI",
      "disabilities": ["HAND", "VIS"],
      "postcode": "AB12 3DE",
      "uasc_flag": true,
      "uasc_end_date": "2022-06-14",
      "purge": false
    },
    "health_and_wellbeing": {
      "sdq_assessments": [ { "date": "2022-06-14", "score": 20 } ],
      "purge": false
    },
    "social_care_episodes": [
      {
        "social_care_episode_id": "ABC123456",
        "referral_date": "2022-06-14",
        "referral_source": "1C",
        "referral_no_further_action_flag": false,
        "care_worker_details": [ { "worker_id": "ABC123", "start_date": "2022-06-14", "end_date": "2022-06-14" } ],
        "child_and_family_assessments": [ { "child_and_family_assessment_id": "ABC123456", "start_date": "2022-06-14", "authorisation_date": "2022-06-14", "factors": ["1C", "4A"], "purge": false } ],
        "child_in_need_plans": [ { "child_in_need_plan_id": "ABC123456", "start_date": "2022-06-14", "end_date": "2022-06-14", "purge": false } ],
        "section_47_assessments": [ { "section_47_assessment_id": "ABC123456", "start_date": "2022-06-14", "icpc_required_flag": true, "icpc_date": "2022-06-14", "end_date": "2022-06-14", "purge": false } ],
        "child_protection_plans": [ { "child_protection_plan_id": "ABC123456", "start_date": "2022-06-14", "end_date": "2022-06-14", "purge": false } ],
        "child_looked_after_placements": [ { "child_looked_after_placement_id": "ABC123456", "start_date": "2022-06-14", "start_reason": "S", "placement_type": "K1", "postcode": "AB12 3DE", "end_date": "2022-06-14", "end_reason": "E3", "change_reason": "CHILD", "purge": false } ],
        "adoption": { "initial_decision_date": "2022-06-14", "matched_date": "2022-06-14", "placed_date": "2022-06-14", "purge": false },
        "care_leavers": { "contact_date": "2022-06-14", "activity": "F2", "accommodation": "D", "purge": false },
        "closure_date": "2022-06-14",
        "closure_reason": "RC7",
        "purge": false
      }
    ],
    "purge": false
  }
]
'@


# main Start
$scriptStartTime      = Get-Date
$scriptStartTimeStamp = $scriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")
Write-Host ""
Write-Host ""
Write-Host "CSC API staging build connectivity tests, v0.2.0"
Write-Host "###################################################################"
Write-Host "###       Script Execution Started, $scriptStartTimeStamp       ###"
Write-Host "###################################################################"
Write-Host ""
# Sanity checks
$missing = @()
if (-not $token_endpoint) { $missing += 'token_endpoint' }
if (-not $client_id)      { $missing += 'client_id' }
if (-not $client_secret)  { $missing += 'client_secret' }
if (-not $scope)          { $missing += 'scope' }
if (-not $api_endpoint)   { $missing += 'api_endpoint' }
if (-not $la_code)        { $missing += 'la_code' }
if (-not $supplier_key)   { $missing += 'supplier_key' }

if ($missing.Count -gt 0) {
  Write-Host ("Missing required vars, {0}" -f ($missing -join ', '))
  exit 1
}
if ($token_endpoint -notmatch '/oauth2/v2\.0/token') {
  Write-Host "token_endpoint must be AAD v2 path, example, https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token"
  exit 1
}
if ($scope -notmatch '\.default$') { $scope = "$scope/.default" }

$endpoint = ($api_endpoint.TrimEnd('/')) + "/children_social_care_data/$la_code/children"
Write-Host "Token URL, $token_endpoint"
Write-Host "Scope URI, $scope"
if ($client_id.Length -ge 8) {
  #Write-Host "Client ID, $($client_id.Substring(0,[Math]::Min(8,$client_id.Length)))****"

} else {
  Write-Host "Client ID, ****"
}
Write-Host "Endpoint, $endpoint"


#Optional token probe
if ($TOKEN_PROBE_ONLY) {
  $ok = Token-Probe
  if ($ok) { exit 0 } else { exit 1 }
}


# choose payload
# allowed, empty, min, full, default to min
switch ($SEND_BODY_MODE.ToLower()) {
  'empty' { $payload = $payload_empty; break }
  'min'   { $payload = $payload_min; break }
  'full'  { $payload = $payload_full; break }
  default { $payload = $payload_min }
}

# append la_code to la_child_id for all records in payload (min and full)
# eg, child1234 + 845 becomes child1234845
# parse json to objects, adjust, then reserialise
# append la_code to la_child_id for all records, keep json as an array
try {
    $laCodeStr  = [string]$la_code                         # ensure string
    $payloadObj = ConvertFrom-Json -InputObject $payload -ErrorAction Stop

    # force array wrapper even when there is only one record
    if ($payloadObj -is [pscustomobject]) { $payloadObj = @($payloadObj) }

    foreach ($rec in $payloadObj) {
        if ($rec.la_child_id) {
            # optional guard, do not double append if already suffixed
            if ($rec.la_child_id -notmatch "$([regex]::Escape($laCodeStr))$") {
                $rec.la_child_id = "$($rec.la_child_id)$laCodeStr"
                $adjChild_Id = "$($rec.la_child_id)$laCodeStr" # debug only
            }
        }
    }

    # serialise as a single json array string, not per item
    $payload = ConvertTo-Json -InputObject $payloadObj -Depth 50 -Compress
} catch {
    Write-Host "warning, could not adjust la_child_id, sending original payload"
}


Write-Host ("payload mode, {0}, bytes, {1}" -f ($SEND_BODY_MODE.ToLower()), ([Text.Encoding]::UTF8.GetByteCount($payload)))




#LA Token
$token = Get-OAuthToken
if (-not $token) {
  Write-Host "Cannot continue without token."
  if ($ENABLE_DIAGNOSTICS) {
    Write-Host "Connectivity diagnostics for token endpoint"
    $script:DiagData = Get-ConnectivityDiagnostics -Url $token_endpoint
  }
  exit 401
}


# POST
$headers = @{
  'Authorization' = "Bearer $token"
  'SupplierKey'   = $supplier_key
  'Accept'        = 'application/json'
  'Content-Type'  = 'application/json'
  'User-Agent'    = 'D2I-CSC-Client/0.3'
}

$code = $null
$desc = $null
$requestId = $null
$errBody = $null

$swCall = [System.Diagnostics.Stopwatch]::StartNew()
try {
  $resp = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec $timeoutSec -ErrorAction Stop
  $swCall.Stop()
  $code = 200
  $desc = Describe-Code 200
  Write-Host "POST OK in $([math]::Round($swCall.Elapsed.TotalSeconds,2))s"
  if ($resp) { Write-Host "Raw API response follows"; $resp | Out-String | Write-Host }
} catch {
  $swCall.Stop()
  if ($_.Exception.Response) {
    $code = $_.Exception.Response.StatusCode.value__
    $desc = Describe-Code $code
    Write-Host ("HTTP error, {0} ({1}) after {2:N2}s" -f $code, $desc, $swCall.Elapsed.TotalSeconds)
    try {
      $reader  = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $errBody = $reader.ReadToEnd()
      if ($errBody) {
        $preview = $errBody.Substring(0, [Math]::Min(800, $errBody.Length))
        Write-Host "Error body preview:"
        Write-Host $preview
      }
    } catch {}
    if ($ENABLE_DIAGNOSTICS -and ($DIAG_ON_HTTP_CODES -contains [int]$code)) {
      Write-Host "Connectivity diagnostics for API endpoint"
      $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint
    }
  } else {
    Write-Host ("Transport error after {0:N2}s, {1}" -f $swCall.Elapsed.TotalSeconds, $_.Exception.Message)
    if ($ENABLE_DIAGNOSTICS) {
      $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint
    }
  }
}

#output Summary
$scriptEndTime = Get-Date
$scriptTotalSeconds = ($scriptEndTime - $scriptStartTime).TotalSeconds

Write-Host ""
Write-Host ("Fake Child ID sent: {0}" -f ($adjChild_Id -as [string]))
#Write-Host ("Started, {0}" -f $scriptStartTimeStamp)
#Write-Host ("Endpoint, {0}" -f $endpoint)
#Write-Host ("Mode and bytes, {0} , {1}" -f $SEND_BODY_MODE, [Text.Encoding]::UTF8.GetByteCount($payload))
Write-Host ("HTTP Status, {0}" -f ($code -as [string]))
Write-Host ("Status Description, {0}" -f ($desc -as [string]))
#Write-Host ("Total runtime seconds, {0:N2}" -f $scriptTotalSeconds)

if ($script:DiagData -and $script:DiagData.Ran) {
  Write-Host "---- DIAG SUMMARY ----"
  if ($script:DiagData.Dns)            { Write-Host ("DNS , {0}" -f $script:DiagData.Dns) }
  if ($script:DiagData.Tcp)            { Write-Host ("TCP , {0}" -f $script:DiagData.Tcp) }
  if ($script:DiagData.TlsProtocol)    { Write-Host ("TLS , {0}" -f $script:DiagData.TlsProtocol) }
  if ($script:DiagData.TlsCert)        { Write-Host ("TLS Cert , {0}" -f $script:DiagData.TlsCert) }
  if ($script:DiagData.TlsIssuer)      { Write-Host ("TLS Issuer , {0}" -f $script:DiagData.TlsIssuer) }
  if ($script:DiagData.TlsPolicyErrors){ Write-Host ("TLS Policy , {0}" -f $script:DiagData.TlsPolicyErrors) }
  if ($script:DiagData.HeadRoot)       { Write-Host ("HEAD Root , {0}" -f $script:DiagData.HeadRoot) }
  if ($script:DiagData.HeadPath)       { Write-Host ("HEAD Endpoint , {0}" -f $script:DiagData.HeadPath) }
  if ($script:DiagData.Note)           { Write-Host ("Diag Note , {0}" -f $script:DiagData.Note) }
}

Write-Host ""
Write-Host "### Script Execution Ended, COPY ABOVE OUTPUT AND RETURN TO D2I ###"
Write-Host "###################################################################"



$exitCode = if ($code -ge 200 -and $code -lt 300) { 0 } elseif ($code) { [int]$code } else { 1 }
exit $exitCode

