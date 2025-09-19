
# D2I minimal CSC API connectivity test (PowerShell 5.0)(POST only)
# - OAuth client credentials
# - POST either [] or hard-coded record


# ----------- LA Config -----------
$api_endpoint   = "https://REPLACE_ME_BASE_URL"          # no trailing slash
$token_endpoint = "https://REPLACE_ME_TOKEN_URL"
$client_id      = "REPLACE_ME_CLIENT_ID"
$client_secret  = "REPLACE_ME_CLIENT_SECRET"
$scope          = "REPLACE_ME_SCOPE"
$supplier_key   = "REPLACE_ME_SUPPLIER_KEY"

$la_code        = 000   # e.g., 846
# ----------- LA Config END -----------








# ----------- Config OVERIDE -----------
# D2I Tests
# 
# ----------- Config OVERIDE END -----------


# pick up when didnt reach HTTP at all (DNS/TCP/TLS/proxy path issues), when $_\.Exception.Response is null
# Diagnostics toggles
$ENABLE_DIAGNOSTICS = $true
$DIAG_ON_HTTP_CODES = @(401,403,407,408,413,415,429,500,502,503,504)  # when to run diags even if HTTP reached
$DIAG_HTTP_PROBE    = $true  # do quick HEAD probes as part of diagnostics





$scriptStartTime      = Get-Date
$scriptStartTimeStamp = $scriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Started: $scriptStartTimeStamp ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray


$SEND_BODY_MODE = 'full'  # or 'empty' or 'min', fake payload(POST [])
$timeoutSec     = 60



# PS5 TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----------- Utils -----------
function Describe-Code([int]$c) {
    switch ($c) {
        400 { "Malformed payload (400 BadRequest)" }
        401 { "Invalid token (401 Unauthorised)" }
        403 { "Forbidden / access disallowed (403)" }
        405 { "Method not allowed (405)" }
        408 { "Request timeout (408) — network/WAF/proxy" }
        413 { "Payload too large (413)" }
        415 { "Unsupported media type (415)" }
        429 { "Rate limited (429)" }
        500 { "Internal server error (500)" }
        502 { "Bad gateway (502) — upstream proxy/gateway" }
        503 { "Service unavailable (503)" }
        504 { "Gateway timeout (504) — upstream path issue" }
        default {
            try { return ([System.Net.HttpStatusCode]$c).ToString() }
            catch { return "Other/Unexpected ($c)" }
        }
    }
}


function Describe-WebExceptionStatus($status) {
    switch ($status) {
        'NameResolutionFailure'     { 'DNS resolution failed (sender-side or proxy DNS)' }
        'ConnectFailure'            { 'TCP connect failed (firewall/blocked port)' }
        'ConnectionClosed'          { 'Connection closed prematurely' }
        'ReceiveFailure'            { 'Receive failed (proxy/WAF/SSL inspection?)' }
        'SendFailure'               { 'Send failed (MTU/proxy/SSL inspection?)' }
        'Timeout'                   { 'Connection/request timed out (network/WAF)' }
        'TrustFailure'              { 'Certificate trust failed' }
        'SecureChannelFailure'      { 'TLS handshake failed (protocol/cipher/inspection)' }
        'ProxyNameResolutionFailure'{ 'Proxy DNS failed' }
        'ProxyAuthenticationRequired'{ 'Proxy requires authentication (407)' }
        default { [string]$status }
    }
}



function Get-OAuthToken {
    param(
        [string]$TokenUrl, [string]$ClientId, [string]$ClientSecret, [string]$Scope
    )
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $body `
                                  -ContentType "application/x-www-form-urlencoded" `
                                  -ErrorAction Stop
        $sw.Stop()
        Write-Host ("Token fetched in {0:N2}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
        return $resp.access_token
    } catch {
        $sw.Stop()
        Write-Host ("Token request failed after {0:N2}s: {1}" -f $sw.Elapsed.TotalSeconds, $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}


function Get-ConnectivityDiagnostics {
    param([Parameter(Mandatory=$true)][string]$Url)

    try { $u = [uri]$Url } catch { Write-Host "DIAG: Bad URL: $Url" -ForegroundColor Yellow; return }
    $host = $u.Host
    $port = if ($u.IsDefaultPort) { if ($u.Scheme -eq 'https') { 443 } else { 80 } } else { $u.Port }

    Write-Host "----- CONNECTIVITY DIAGNOSTICS -----" -ForegroundColor Cyan

    # DNS
    try {
        $ips = @()
        try {
            $ips = (Resolve-DnsName -Name $host -Type A -ErrorAction Stop).IPAddress
        } catch {
            $ips = [System.Net.Dns]::GetHostAddresses($host) | ForEach-Object { $_.IPAddressToString }
        }
        Write-Host ("DNS   : {0} -> {1}" -f $host, (($ips | Select-Object -Unique) -join ", "))
    } catch {
        Write-Host ("DNS   : FAILED ({0})" -f $_.Exception.Message) -ForegroundColor Yellow
    }

    # TCP + TLS
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($host, $port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { $tcp.Close(); throw "TCP connect timeout" }
        $tcp.EndConnect($iar)
        Write-Host ("TCP   : Connected to {0}:{1}" -f $host, $port)

        # TLS handshake (also reveal MITM/inspection via issuer)
        $script:__sslErrors = [System.Net.Security.SslPolicyErrors]::None
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { param($s,$cert,$chain,$errors) $script:__sslErrors = $errors; $true })
        $ssl.AuthenticateAsClient($host)
        $cert   = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
        $proto  = $ssl.SslProtocol
        Write-Host ("TLS   : OK ({0})  Cert: {1}  Issuer: {2}" -f $proto, $cert.Subject, $cert.Issuer)
        if ($script:__sslErrors -ne [System.Net.Security.SslPolicyErrors]::None) {
            Write-Host ("TLS   : Policy errors: {0}" -f $script:__sslErrors) -ForegroundColor Yellow
        }

        # --- cert validity, SANs, chain summary, MITM hints ---
        try {
            $notBefore = $cert.NotBefore
            $notAfter  = $cert.NotAfter
            $daysLeft  = [int]([datetime]$notAfter - (Get-Date)).TotalDays
            Write-Host ("TLS   : Cert valid {0} to {1} (~{2} days left)" -f $notBefore.ToString('yyyy-MM-dd'), $notAfter.ToString('yyyy-MM-dd'), $daysLeft)

            # SANs
            $san = ($cert.Extensions | Where-Object { $_.Oid.FriendlyName -eq 'Subject Alternative Name' })
            if ($san) {
                $data = $san.Format($true) -replace "`r?`n", '; ' -replace '\s+', ' '
                Write-Host ("TLS   : SANs -> {0}" -f $data)
            }

            # Hostname match
            $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
            $null = $chain.Build($cert)
            $nameMatch = [System.Net.ServicePointManager]::CheckCertificateName($cert, $host)
            Write-Host ("TLS   : Hostname match -> {0}" -f $nameMatch)

            if ($chain.ChainStatus -and $chain.ChainStatus.Length -gt 0) {
                $issues = ($chain.ChainStatus | ForEach-Object { $_.Status }) -join ', '
                Write-Host ("TLS   : Chain issues -> {0}" -f $issues) -ForegroundColor Yellow
            }

            # Heuristic: known inspection issuers
            $issuer = $cert.Issuer
            $maybeMitm = @('Zscaler','Blue Coat','Symantec','Fortinet','Palo Alto','Cisco','Sophos','Netskope') | Where-Object { $issuer -match $_ }
            if ($maybeMitm) {
                Write-Host ("TLS   : Likely TLS inspection by: {0}" -f ($maybeMitm -join ', ')) -ForegroundColor Yellow
            }
        } catch {}

        $ssl.Close(); $tcp.Close()
    } catch {
        Write-Host ("TCP/TLS: FAILED ({0})" -f $_.Exception.Message) -ForegroundColor Yellow
    }

    # Proxy quick readouts
    try {
        $winhttp = (netsh winhttp show proxy) 2>$null
        if ($winhttp) {
            $line = ($winhttp -split "`r?`n" | Select-String -Pattern 'Direct access|Proxy Server').Line
            if ($line) { Write-Host ("Proxy : {0}" -f ($line -join " | ")) }
        }
    } catch {}

    # --- .NET default proxy + env proxies ---
    try {
        $defaultProxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($defaultProxy) {
            $proxyUri = $defaultProxy.GetProxy($u)
            $bypass   = $defaultProxy.IsBypassed($u)
            Write-Host ("Proxy(.NET): {0}  (bypass={1})" -f ($proxyUri -as [string]), $bypass)
        }
        if ($env:HTTPS_PROXY) { Write-Host ("Env HTTPS_PROXY: {0}" -f $env:HTTPS_PROXY) }
        elseif ($env:HTTP_PROXY) { Write-Host ("Env HTTP_PROXY : {0}" -f $env:HTTP_PROXY) }
        if ($env:NO_PROXY) { Write-Host ("Env NO_PROXY    : {0}" -f $env:NO_PROXY) }
    } catch {}

    # --- optional HTTP HEAD probes ---
    if ($DIAG_HTTP_PROBE) {
        try {
            $rootUrl = "{0}://{1}/" -f $u.Scheme, $u.Host
            $rootResp = Invoke-WebRequest -Uri $rootUrl -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Write-Host ("HTTP  : HEAD {0} -> {1}" -f $rootUrl, $rootResp.StatusCode)
            if ($rootResp.Headers['Server']) { Write-Host ("HTTP  : Server={0}" -f $rootResp.Headers['Server']) }
            if ($rootResp.Headers['Via'])    { Write-Host ("HTTP  : Via={0}"    -f $rootResp.Headers['Via']) }
        } catch {
            Write-Host ("HTTP  : HEAD {0} FAILED ({1})" -f $rootUrl, $_.Exception.Message) -ForegroundColor Yellow
        }
        try {
            $pathResp = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Write-Host ("HTTP  : HEAD {0} -> {1}" -f $Url, $pathResp.StatusCode)
        } catch {
            Write-Host ("HTTP  : HEAD {0} FAILED ({1})" -f $Url, $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    Write-Host "------------------------------------" -ForegroundColor Cyan
}



# ----------- Build endpoint -----------
$endpoint = ($api_endpoint.TrimEnd('/')) + "/children_social_care_data/$la_code/children"
#Debug
# Write-Host "Endpoint: $endpoint" -ForegroundColor Gray

# ----------- OAuth -----------
$token = Get-OAuthToken -TokenUrl $token_endpoint -ClientId $client_id -ClientSecret $client_secret -Scope $scope
if (-not $token) { 
    Write-Host "Cannot continue without token." -ForegroundColor Red
    $exitCode = 1
    goto END_OF_SCRIPT
}

$headers = @{
    "Authorization" = "Bearer $token"
    "SupplierKey"   = $supplier_key
}

# ----------- Payload options -----------
$emptyArrayPayload = "[]" # just empty

# minimum payload
$hardcodedPayloadMin = @' 
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
    }
    ]
'@

# DfE spec 0.8.0 sample record (array-wrapped)
$hardcodedPayloadFull = @'
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
      "sdq_assessments": [
        { "date": "2022-06-14", "score": 20 }
      ],
      "purge": false
    },
    "social_care_episodes": [
      {
        "social_care_episode_id": "ABC123456",
        "referral_date": "2022-06-14",
        "referral_source": "1C",
        "referral_no_further_action_flag": false,
        "care_worker_details": [
          { "worker_id": "ABC123", "start_date": "2022-06-14", "end_date": "2022-06-14" }
        ],
        "child_and_family_assessments": [
          {
            "child_and_family_assessment_id": "ABC123456",
            "start_date": "2022-06-14",
            "authorisation_date": "2022-06-14",
            "factors": ["1C", "4A"],
            "purge": false
          }
        ],
        "child_in_need_plans": [
          {
            "child_in_need_plan_id": "ABC123456",
            "start_date": "2022-06-14",
            "end_date": "2022-06-14",
            "purge": false
          }
        ],
        "section_47_assessments": [
          {
            "section_47_assessment_id": "ABC123456",
            "start_date": "2022-06-14",
            "icpc_required_flag": true,
            "icpc_date": "2022-06-14",
            "end_date": "2022-06-14",
            "purge": false
          }
        ],
        "child_protection_plans": [
          {
            "child_protection_plan_id": "ABC123456",
            "start_date": "2022-06-14",
            "end_date": "2022-06-14",
            "purge": false
          }
        ],
        "child_looked_after_placements": [
          {
            "child_looked_after_placement_id": "ABC123456",
            "start_date": "2022-06-14",
            "start_reason": "S",
            "placement_type": "K1",
            "postcode": "AB12 3DE",
            "end_date": "2022-06-14",
            "end_reason": "E3",
            "change_reason": "CHILD",
            "purge": false
          }
        ],
        "adoption": {
          "initial_decision_date": "2022-06-14",
          "matched_date": "2022-06-14",
          "placed_date": "2022-06-14",
          "purge": false
        },
        "care_leavers": {
          "contact_date": "2022-06-14",
          "activity": "F2",
          "accommodation": "D",
          "purge": false
        },
        "closure_date": "2022-06-14",
        "closure_reason": "RC7",
        "purge": false
      }
    ],
    "purge": false
  }
]
'@

# cwitch depending on which payload 
switch ($SEND_BODY_MODE.ToLower()) {
    "empty" { $body = $emptyArrayPayload; break }
    "full"  { $body = $hardcodedPayloadFull; break }
    "min"   { $body = $hardcodedPayloadMin; break }
    default {
        Write-Host "Unknown SEND_BODY_MODE '$SEND_BODY_MODE' (use empty|full|min)" -ForegroundColor Yellow
        $body = $emptyArrayPayload
    }
}
$bodyBytes = [Text.Encoding]::UTF8.GetByteCount($body)
#Debug
# Write-Host ("Mode: {0}  |  Bytes: {1}" -f $SEND_BODY_MODE, $bodyBytes) -ForegroundColor Gray

# ----------- POST -----------
$swCall  = [System.Diagnostics.Stopwatch]::StartNew()
$code    = $null
$desc    = $null
$requestId = $null

try {
    $resp = Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers `
                              -ContentType "application/json" -Body $body `
                              -UseBasicParsing -TimeoutSec $timeoutSec -ErrorAction Stop

    $swCall.Stop()
    $code = $resp.StatusCode
    $desc = Describe-Code $code

    # Pull request-id header if present
    if ($resp -and $resp.Headers) {
        $requestId = $resp.Headers["x-request-id"]
        if (-not $requestId) { $requestId = $resp.Headers["Request-Id"] }
        if (-not $requestId) { $requestId = $resp.Headers["X-Correlation-ID"] }
    }
    #Debug
    #Write-Host ("HTTP {0} ({1:N2}s)" -f $code, $swCall.Elapsed.TotalSeconds) -ForegroundColor Green

} catch {
    $swCall.Stop()
    $code = $null; $desc = $null; $errBody = $null

    if ($_.Exception.Response) {
        # reached HTTP endpoint (receiver/gateway/app)
        $code = $_.Exception.Response.StatusCode.value__
        $desc = Describe-Code $code

        try {
            $requestId = $_.Exception.Response.Headers["x-request-id"]
            if (-not $requestId) { $requestId = $_.Exception.Response.Headers["Request-Id"] }
            if (-not $requestId) { $requestId = $_.Exception.Response.Headers["X-Correlation-ID"] }
        } catch {}

        Write-Host ("HTTP error: {0} ({1}) ({2:N2}s)" -f $code, $desc, $swCall.Elapsed.TotalSeconds) -ForegroundColor Yellow

        try {
            $reader  = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $errBody = $reader.ReadToEnd()
            if ($errBody) {
                $preview = $errBody.Substring(0, [Math]::Min(400, $errBody.Length))
                Write-Host "Error body preview:" -ForegroundColor DarkGray
                Write-Host $preview
            }
        } catch {}

        # diagnostics on HTTP errors, uncomment:
        # if ($ENABLE_DIAGNOSTICS) { Get-ConnectivityDiagnostics -Url $endpoint }
        # Or use code allowlist:
        if ($ENABLE_DIAGNOSTICS -and ($DIAG_ON_HTTP_CODES -contains [int]$code)) { Get-ConnectivityDiagnostics -Url $endpoint }

    } else {
        # did NOT reach HTTP (sender-side path issue: DNS/TCP/TLS/proxy)
        if ($_.Exception -is [System.Net.WebException]) {
            Write-Host ("WebException.Status: {0}" -f $_.Exception.Status) -ForegroundColor DarkGray
            # Common status:
            # NameResolutionFailure / ConnectFailure / Timeout / TrustFailure / SecureChannelFailure / ProxyAuthenticationRequired
            $hint = Describe-WebExceptionStatus $_.Exception.Status
            Write-Host ("Transport hint     : {0}" -f $hint) -ForegroundColor DarkGray
        }

        $desc = "Transport/Other error"
        Write-Host ("Transport error after {0:N2}s: {1}" -f $swCall.Elapsed.TotalSeconds, $_.Exception.Message) -ForegroundColor DarkYellow

        if ($ENABLE_DIAGNOSTICS) { Get-ConnectivityDiagnostics -Url $endpoint }
    }
}








# ----------- BASIC ENV DETS FOR REF -----------
# Minimal environment details (PS 5.0-safe)
$runUser   = $env:USERNAME
$psVersion = $PSVersionTable.PSVersion.ToString()

# Windows version (CIM with WMI fallback)
$os = $null
try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch {
    try { $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop } catch {}
}
$osCaption = if ($os) { $os.Caption } else { "<unknown>" }
$osVersion = if ($os) { $os.Version } else { "<unknown>" }
$osBuild   = if ($os) { $os.BuildNumber } else { "<unknown>" }





# ----------- CLEAN UP -----------
$preview=""

# ----------- D2I COPY-ME block -----------
$scriptEndTime       = Get-Date
$scriptTotalSeconds  = ($scriptEndTime - $scriptStartTime).TotalSeconds

Write-Host ""
Write-Host "===== COPY LINES BETWEEN THESE MARKERS AND RETURN TO D2I =====" -ForegroundColor Cyan
Write-Host ("User               : {0}" -f $runUser)
Write-Host ("PowerShell         : {0}" -f $psVersion)
Write-Host ("Windows            : {0} (Version {1}, Build {2})" -f $osCaption, $osVersion, $osBuild)

Write-Host ("Started            : {0}" -f $scriptStartTimeStamp)
Write-Host ("Endpoint           : {0}" -f $endpoint)
Write-Host ("Mode/Bytes         : {0} / {1}" -f $SEND_BODY_MODE, $bodyBytes)
Write-Host ("HTTP Status        : {0}" -f ($code -as [string]))
Write-Host ("Status Description : {0}" -f ($desc   -as [string]))
Write-Host ("Request ID         : {0}" -f ($requestId -as [string]))
Write-Host ("Total runtime (s)  : {0:N2}" -f $scriptTotalSeconds)
# Exit code preview (what script will return)
$exitCode = if ($code -ge 200 -and $code -lt 300) { 0 } elseif ($code) { [int]$code } else { 1 }
Write-Host ("Planned Exit Code  : {0}" -f $exitCode)
Write-Host ("Preview            : {0}" -f $preview)
Write-Host "===== END D2I COPY BLOCK =====" -ForegroundColor Cyan
Write-Host ""


$scriptEndStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Ended: $scriptEndStamp ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray

# Exit for CI / calling shells
if ($null -eq $exitCode) { $exitCode = 1 }
exit $exitCode
