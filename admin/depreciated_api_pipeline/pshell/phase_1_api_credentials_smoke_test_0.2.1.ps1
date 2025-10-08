<#
.SYNOPSIS
  CSC API smoke test, AAD v2 client credentials, token and POST sender

.DESCRIPTION
  Single token call (AAD v2 client credentials) and one POST of a minimal
  JSON payload to CSC endpoint. Plug your LA values into labelled
  Config block. Prints AAD errors when token fails plus connectivity diagnostics

.PARAMETER ApiTimeout
  Per-call timeout in seconds for both token request and POST (default 30, 5–120)


.NOTES
  File   : phase_1_api_credentials_smoke_test.ps1
  Author : D2I
  Date   : 08/10/2025

.EXAMPLES
  Optional guidance if running this as CLI

  # Direct (no proxy), default timeout
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\phase_1_api_credentials_smoke_test.ps1

  # Direct with custom timeout (60s)
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\phase_1_api_credentials_smoke_test.ps1 -ApiTimeout 60

  # LA feedback welcomed! 
#>
[CmdletBinding()]
param(
  [ValidateRange(5,120)] [int]$ApiTimeout = 30
)


$timeoutSec = $ApiTimeout


$VERSION = '0.2.1'
Write-Host ("CSC API staging build: v{0}" -f $VERSION)

# ----------- LA Config START -----------
# REQUIRED, replace the details in quotes below with your LA's credentials as supplied by DfE
# from https://pp-find-and-use-an-api.education.gov.uk/ (once logged in), transfer the following details into the quotes:

$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1" # 'Base URL' - Shouldn't need to change


# From the 'Native OAuth Application-flow' block
$client_id       = "OAUTH_CLIENT_ID_CODE" # 'OAuth Client ID'
$client_secret   = "NATIVE_OAUTH_PRIMARY_KEY_CODE"  # 'Native OAuth Application-flow' - 'Primary key' or 'Secondary key'
$scope           = "OAUTH_SCOPE_LINK" # 'OAuth Scope'
$token_endpoint  = "OAUTH_TOKEN_ENDPOINT" # From the 'Native OAuth Application-flow' block - 'OAuth token endpoint'

# From 'subscription key' block
$supplier_key    = "SUBSCRIPTION_PRIMARY_KEY_CODE" # From the 'subscription key' block - 'Primary key' or 'Secondary key'


$la_code         = "000" # Change to your 3 digit LA code(within quotes)

# ----------- LA Config END -----------






# ----------- Config OVERIDE -----------
# D2I Overide block

# --------- Config OVERIDE END ---------





# pick up when didnt reach HTTP at all (DNS/TCP/TLS/proxy path issues), when $_\.Exception.Response is null
# diag opts1
$ENABLE_DIAGNOSTICS = $true
$DIAG_ON_HTTP_CODES = @(204,401,403,407,408,413,415,429,500,502,503,504)  # when to run diags even if HTTP reached
$DIAG_HTTP_PROBE    = $true  # do quick HEAD probes as part of diagnostic

# diag opts2
$DIAG_PRINT   = $false   # live spam off; print inside COPY block instead
$DIAG_CAPTURE = $true
$script:DiagData = $null

$scriptStartTime      = Get-Date
$scriptStartTimeStamp = $scriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")
Write-Host "#####################################################" -ForegroundColor Gray
Write-Host "### Script Execution Started: $scriptStartTimeStamp ###" -ForegroundColor Gray
Write-Host "#####################################################" -ForegroundColor Gray

# PS5 TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::Expect100Continue = $false

# ----------- Utils -----------
function Describe-Code([int]$c) {
  switch ($c) {
    204 { "No content (204)" }
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
    default { try { ([System.Net.HttpStatusCode]$c).ToString() } catch { "Other/Unexpected ($c)" } }
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
  $form = "client_id=$([uri]::EscapeDataString($ClientId))" +
          "&client_secret=$([uri]::EscapeDataString($ClientSecret))" +
          "&scope=$([uri]::EscapeDataString($Scope))" +
          "&grant_type=client_credentials"

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $resp = Invoke-RestMethod -Uri $TokenUrl -Method Post `
         -Body $form `
         -ContentType "application/x-www-form-urlencoded" `
         -TimeoutSec $timeoutSec `
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

    $info = [ordered]@{
        Ran             = $true
        Dns             = $null
        Tcp             = $null
        TlsProtocol     = $null
        TlsCert         = $null
        TlsIssuer       = $null
        TlsPolicyErrors = $null
        ProxyWinHttp    = $null
        ProxyDotNet     = $null
        ProxyBypass     = $null
        EnvHttpProxy    = $env:HTTP_PROXY
        EnvHttpsProxy   = $env:HTTPS_PROXY
        EnvNoProxy      = $env:NO_PROXY
        HeadRoot        = $null
        HeadPath        = $null
        Note            = $null
    }
    function _p($t,$c='Gray'){ if($script:DIAG_PRINT){ Write-Host $t -ForegroundColor $c } }

    try { $uri = [uri]$Url } catch { _p "DIAG: Bad URL: $Url" Yellow; $info.Note="bad url"; return [pscustomobject]$info }
    $targetHost = $uri.Host
    $targetPort = if ($uri.IsDefaultPort) { if ($uri.Scheme -eq 'https') { 443 } else { 80 } } else { $uri.Port }

    _p "----- CONNECTIVITY DIAGNOSTICS -----" Cyan

    # DNS
    try {
        $ips = @()
        try { $ips = (Resolve-DnsName -Name $targetHost -Type A -ErrorAction Stop).IPAddress }
        catch { $ips = [System.Net.Dns]::GetHostAddresses($targetHost) | ForEach-Object { $_.IPAddressToString } }
        $info.Dns = ("{0} -> {1}" -f $targetHost, (($ips | Select-Object -Unique) -join ", "))
        _p ("DNS   : {0}" -f $info.Dns)
    } catch { $info.Dns = "FAILED: " + $_.Exception.Message; _p ("DNS   : {0}" -f $info.Dns) Yellow }

    # Proxy (WinHTTP)
    try {
        $winhttp = (netsh winhttp show proxy) 2>$null
        if ($winhttp) {
            $line = ($winhttp -split "`r?`n" | Select-String -Pattern 'Direct access|Proxy Server').Line
            if ($line) { $info.ProxyWinHttp = ($line -join " | "); _p ("Proxy : {0}" -f $info.ProxyWinHttp) }
        }
    } catch {}

    # TCP + TLS (honour .NET proxy)
    $def = $null; $puri=$null; $bypass=$true
    try {
        $def = [System.Net.WebRequest]::DefaultWebProxy
        if ($def) { $puri = $def.GetProxy($uri); $bypass = $def.IsBypassed($uri) }
        $info.ProxyDotNet = ($puri -as [string]); $info.ProxyBypass = $bypass
        if($info.ProxyDotNet){ _p ("Proxy(.NET): {0}  (bypass={1})" -f $info.ProxyDotNet,$info.ProxyBypass) }
    } catch {}

    try {
        $useProxy = ($def -and -not $bypass -and $puri -and $puri.Scheme -eq 'http')
        if ($useProxy) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($puri.Host, $puri.Port)
            $net = $tcp.GetStream()
            $sw  = New-Object System.IO.StreamWriter($net); $sw.NewLine="`r`n"; $sw.AutoFlush=$true
            $sr  = New-Object System.IO.StreamReader($net)
            $sw.WriteLine(("CONNECT {0}:{1} HTTP/1.1" -f $targetHost,$targetPort))
            $sw.WriteLine(("Host: {0}:{1}" -f $targetHost,$targetPort))
            $sw.WriteLine("Proxy-Connection: Keep-Alive")
            $sw.WriteLine()
            $status = $sr.ReadLine()
            if ($status -notmatch '^HTTP/1\.\d 200') { throw "Proxy CONNECT failed: $status" }
            while (($line = $sr.ReadLine()) -and $line -ne '') { }
            $info.Tcp = ("Proxy tunnel OK via {0}:{1}" -f $puri.Host,$puri.Port)
            _p ("TCP   : {0}" -f $info.Tcp)
            $script:__sslErrors = [System.Net.Security.SslPolicyErrors]::None
            $ssl = New-Object System.Net.Security.SslStream($net,$false,{ param($s,$cert,$chain,$errors) $script:__sslErrors=$errors; $true })
            $ssl.AuthenticateAsClient($targetHost)
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
            $info.TlsProtocol=$ssl.SslProtocol; $info.TlsCert=$cert.Subject; $info.TlsIssuer=$cert.Issuer; $info.TlsPolicyErrors=$script:__sslErrors
            _p ("TLS   : OK ({0})  Cert: {1}  Issuer: {2}" -f $info.TlsProtocol,$info.TlsCert,$info.TlsIssuer)
            if ($script:__sslErrors -ne [System.Net.Security.SslPolicyErrors]::None) { _p ("TLS   : Policy errors: {0}" -f $script:__sslErrors) Yellow }
            $ssl.Close(); $net.Close(); $tcp.Close()
        } else {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($targetHost,$targetPort,$null,$null)
            if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { $tcp.Close(); throw "TCP connect timeout" }
            $tcp.EndConnect($iar)
            $info.Tcp = ("Connected to {0}:{1}" -f $targetHost,$targetPort); _p ("TCP   : {0}" -f $info.Tcp)
            $script:__sslErrors = [System.Net.Security.SslPolicyErrors]::None
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(),$false,{ param($s,$cert,$chain,$errors) $script:__sslErrors=$errors; $true })
            $ssl.AuthenticateAsClient($targetHost)
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
            $info.TlsProtocol=$ssl.SslProtocol; $info.TlsCert=$cert.Subject; $info.TlsIssuer=$cert.Issuer; $info.TlsPolicyErrors=$script:__sslErrors
            _p ("TLS   : OK ({0})  Cert: {1}  Issuer: {2}" -f $info.TlsProtocol,$info.TlsCert,$info.TlsIssuer)
            if ($script:__sslErrors -ne [System.Net.Security.SslPolicyErrors]::None) { _p ("TLS   : Policy errors: {0}" -f $script:__sslErrors) Yellow }
            $ssl.Close(); $tcp.Close()
        }
    } catch { $info.Note = "TLS fail: " + $_.Exception.Message; _p ("TCP/TLS: FAILED ({0})" -f $_.Exception.Message) Yellow }

    # HEAD probes
    if ($DIAG_HTTP_PROBE) {
        # cap diag timeout so probes don't hang(too long)
        $diagTimeout = [Math]::Min($timeoutSec, 30)
        try {
            $rootUrl = "{0}://{1}/" -f $uri.Scheme,$uri.Host

            Invoke-WebRequest -Uri $rootUrl -Method Head -UseBasicParsing -TimeoutSec $diagTimeout -ErrorAction Stop
            
            $info.HeadRoot = ("{0} -> {1}" -f $rootUrl,$rootResp.StatusCode); _p ("HTTP  : HEAD {0}" -f $info.HeadRoot)
        } catch { $info.HeadRoot = ("{0} FAILED ({1})" -f $rootUrl,$_.Exception.Message); _p ("HTTP  : HEAD {0}" -f $info.HeadRoot) Yellow }
        try {
            $pathResp = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec $diagTimeout -ErrorAction Stop

            $info.HeadPath = ("{0} -> {1}" -f $Url,$pathResp.StatusCode); _p ("HTTP  : HEAD {0}" -f $info.HeadPath)
        } catch { $info.HeadPath = ("{0} FAILED ({1})" -f $Url,$_.Exception.Message); _p ("HTTP  : HEAD {0}" -f $info.HeadPath) Yellow }
    }

    _p "------------------------------------" Cyan
    return [pscustomobject]$info
}

function Get-HeaderValue($headers, [string[]]$names) {
  if (-not $headers) { return $null }
  foreach ($name in $names) {
    foreach ($k in $headers.Keys) {
      if ($k -and $k.ToString().ToLower() -eq $name.ToLower()) {
        $v = $headers[$k]
        if ($v) { return ($v | Select-Object -First 1) }
      }
    }
  }
  return $null
}

# ----------- Build endpoint -----------
$endpoint = ($api_endpoint.TrimEnd('/')) + "/children_social_care_data/$la_code/children"

# ----------- OAuth -----------
$token = Get-OAuthToken -TokenUrl $token_endpoint -ClientId $client_id -ClientSecret $client_secret -Scope $scope

# bail early (and run diags) if token failed
$headers   = $null
$code      = $null
$desc      = $null
$requestId = $null
$swCall    = [System.Diagnostics.Stopwatch]::StartNew()
$bodyBytes = $null   # for reporting only
$payloadLen = 0      # number to print later
$preview = ""        # short preview to print later

if (-not $token) {
    Write-Host "Cannot continue without token." -ForegroundColor Red
    $swCall.Stop()
    $code = 401
    $desc = Describe-Code 401
    if ($ENABLE_DIAGNOSTICS -and ($DIAG_ON_HTTP_CODES -contains 401)) {
        $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint
    }
}
else {
    # ---------- Build smoke-test [] ARRAY payload ----------
    $la_code_str = '{0:D3}' -f [int]$la_code
    $childId     = "Child1234$la_code_str"

    $payload = @(
        @{
            la_child_id  = "$childId"
            mis_child_id = "MIS$la_code_str"
            child_details = @{
                unique_pupil_number = "A123456789012"  # 13-char string; send UPN OR reason, not both
                first_name          = "John"
                surname             = "Doe"
                date_of_birth       = "2022-06-14"
                sex                 = "M"
                ethnicity           = "WBRI"
                postcode            = "AB12 3DE"
                purge               = $false
            }
            purge = $false
        }
    )
    

    # Serialise once, compact
    $body = ConvertTo-Json -InputObject $payload -Depth 10 -Compress

    # --- Preflight sanity: ensure init non-whitespace char is '[' ---
    $trimLead = $body.TrimStart()
    if ($trimLead.Length -eq 0 -or $trimLead[0] -ne '[') {
        $firstCode = if ($trimLead.Length -gt 0) { [int][char]$trimLead[0] } else { -1 }
        Write-Host "Payload sanity check failed. First non-space char: code=$firstCode, char='$($trimLead[0])'" -ForegroundColor Yellow
    }

    # as UTF-8 and send bytes
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $bodyBytes = $utf8NoBom.GetBytes($body)

    # numbers/preview for reporting
    $payloadLen = if ($bodyBytes) { $bodyBytes.Length } else { 0 }
    $preview = if ($bodyBytes -and $bodyBytes.Length -gt 0) {
      [Text.Encoding]::UTF8.GetString($bodyBytes, 0, [Math]::Min($bodyBytes.Length, 200))
    } else { "" }

    # ----------- Headers -----------
    $headers = @{
      "Authorization" = "Bearer $token"
      "SupplierKey"   = $supplier_key
      "Accept"        = "application/json"
      "User-Agent"    = "D2I-CSC-Client/0.3"
    }

    # ----------- POST -----------
    try {
        $resp = Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers `
                  -ContentType "application/json" `
                  -Body $bodyBytes `
                  -UseBasicParsing -TimeoutSec $timeoutSec -ErrorAction Stop

        $swCall.Stop()
        # success path (no exception)
        $code = $resp.StatusCode
        $desc = Describe-Code $code

        # run diags even on success IF code in allow-list (e.g., 204)
        if ($ENABLE_DIAGNOSTICS -and ($DIAG_ON_HTTP_CODES -contains [int]$code)) {
            $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint
        }

        if ($resp -and $resp.Headers) {
            $requestId = Get-HeaderValue $resp.Headers @("x-request-id","request-id","x-correlation-id")
        }
    }
    catch {
        $swCall.Stop()
        $code = $null; $desc = $null; $errBody = $null

        if ($_.Exception.Response) {
            $code = $_.Exception.Response.StatusCode.value__
            $desc = Describe-Code $code

            try {
                $requestId = Get-HeaderValue $_.Exception.Response.Headers @("x-request-id","request-id","x-correlation-id")
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

            if ($ENABLE_DIAGNOSTICS -and ($DIAG_ON_HTTP_CODES -contains [int]$code)) {
                $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint
            }
        }
        else {
            if ($_.Exception -is [System.Net.WebException]) {
                Write-Host ("WebException.Status: {0}" -f $_.Exception.Status) -ForegroundColor DarkGray
                $hint = Describe-WebExceptionStatus $_.Exception.Status
                Write-Host ("Transport hint     : {0}" -f $hint) -ForegroundColor DarkGray
            }
            $desc = "Transport/Other error"
            Write-Host ("Transport error after {0:N2}s: {1}" -f $swCall.Elapsed.TotalSeconds, $_.Exception.Message) -ForegroundColor DarkYellow

            if ($ENABLE_DIAGNOSTICS) {
                $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint
            }
        }
    }
}  # end else(token OK)


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
Write-Host ("Payload Bytes      : {0}" -f $payloadLen)
Write-Host ("HTTP Status        : {0}" -f ($code -as [string]))
Write-Host ("Status Description : {0}" -f ($desc   -as [string]))
$ridOut = if ($requestId) { $requestId } else { "n/a" }
Write-Host ("Request ID         : {0}" -f $ridOut)
Write-Host ("Total runtime (s)  : {0:N2}" -f $scriptTotalSeconds)

# Exit code preview (what script will return)
$exitCode = if ($code -ge 200 -and $code -lt 300) { 0 } elseif ($code) { [int]$code } else { 1 }
Write-Host ("Planned Exit Code  : {0}" -f $exitCode)
Write-Host ("Preview            : {0}" -f $preview)

if ($script:DiagData -and $script:DiagData.Ran) {
    Write-Host "---- DIAG SUMMARY ----" -ForegroundColor DarkCyan
    if ($script:DiagData.Dns)             { Write-Host ("DNS               : {0}" -f $script:DiagData.Dns) }
    if ($script:DiagData.Tcp)             { Write-Host ("TCP               : {0}" -f $script:DiagData.Tcp) }
    if ($script:DiagData.TlsProtocol)     { Write-Host ("TLS               : {0}" -f $script:DiagData.TlsProtocol) }
    if ($script:DiagData.TlsCert)         { Write-Host ("TLS Cert          : {0}" -f $script:DiagData.TlsCert) }
    if ($script:DiagData.TlsIssuer)       { Write-Host ("TLS Issuer        : {0}" -f $script:DiagData.TlsIssuer) }
    if ($script:DiagData.TlsPolicyErrors) { Write-Host ("TLS Policy        : {0}" -f $script:DiagData.TlsPolicyErrors) }
    if ($script:DiagData.ProxyWinHttp)    { Write-Host ("Proxy (WinHTTP)   : {0}" -f $script:DiagData.ProxyWinHttp) }
    if ($script:DiagData.ProxyDotNet)     { Write-Host ("Proxy (.NET)      : {0} (bypass={1})" -f $script:DiagData.ProxyDotNet, $script:DiagData.ProxyBypass) }
    if ($script:DiagData.EnvHttpsProxy)   { Write-Host ("Env HTTPS_PROXY   : {0}" -f $script:DiagData.EnvHttpsProxy) }
    elseif ($script:DiagData.EnvHttpProxy){ Write-Host ("Env HTTP_PROXY    : {0}" -f $script:DiagData.EnvHttpProxy) }
    if ($script:DiagData.EnvNoProxy)      { Write-Host ("Env NO_PROXY      : {0}" -f $script:DiagData.EnvNoProxy) }
    if ($script:DiagData.HeadRoot)        { Write-Host ("HEAD Root         : {0}" -f $script:DiagData.HeadRoot) }
    if ($script:DiagData.HeadPath)        { Write-Host ("HEAD Endpoint     : {0}" -f $script:DiagData.HeadPath) }
    if ($script:DiagData.Note)            { Write-Host ("Diag Note         : {0}" -f $script:DiagData.Note) }
}
Write-Host "===== END D2I COPY BLOCK =====" -ForegroundColor Cyan
Write-Host ""


# Exit for CI / calling shells
if ($null -eq $exitCode) { $exitCode = 1 }
exit $exitCode
