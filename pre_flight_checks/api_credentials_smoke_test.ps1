<#
.SYNOPSIS
  CSC API smoke test using AAD v2 client credentials to fetch token then POST minimal JSON payload

.DESCRIPTION
  Runs one token request and one POST of a small array payload to the CSC endpoint
  Plug LA values into the Config block
  If -Proxy is not supplied and $la_proxy is set, that proxy is used
  Proxy is applied to token and POST calls and .NET DefaultWebProxy is aligned so underlying HTTP honours same settings
  Prints HTTP status, request id, short payload preview and optional connectivity diagnostics

.PARAMETER ApiTimeout
  Per call timeout in seconds for token request and POST (default 30, range 5-120)

.PARAMETER Proxy
  Optional HTTP proxy URL (e.g. http://proxy.myLA.local:8080)
  If omitted and $la_proxy is set, that value is used

.PARAMETER ProxyUseDefaultCredentials
  Use current Windows logon for proxy authentication
  Defaults to true when a proxy is used and no credential flags are provided

.PARAMETER ProxyCredential
  Optional PSCredential for proxy authentication
  Overrides -ProxyUseDefaultCredentials when provided

.NOTES
  File    : api_credentials_smoke_test.ps1
  Author  : D2I
  Date    : 16/10/2025
  TLS     : script forces TLS 1.2
  Proxy   : if -Proxy not provided and $la_proxy is set, it is used; if no creds flags passed, defaults to Windows logon
  Encoding: save as UTF-8 with BOM if you see non ASCII characters

.EXAMPLE
  # Direct (no proxy), default timeout
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\api_credentials_smoke_test.ps1

.EXAMPLE
  # Direct with custom timeout (60s)
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\api_credentials_smoke_test.ps1 -ApiTimeout 60

.EXAMPLE
  # Use explicit proxy with current Windows credentials
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\api_credentials_smoke_test.ps1 `
    -Proxy http://proxy.myLA.local:8080 -ProxyUseDefaultCredentials

.EXAMPLE
  # Use explicit proxy with interactive credentials (prompts once)
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "& { $cred = Get-Credential; `
         .\api_credentials_smoke_test.ps1 `
           -Proxy http://proxy.myLA.local:8080 -ProxyCredential $cred }"

.EXAMPLE
  # Use explicit proxy with non-interactive credentials
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "& { $sec = ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force; `
         $cred = New-Object System.Management.Automation.PSCredential('MYDOMAIN\jdoe',$sec); `
         .\api_credentials_smoke_test.ps1 `
           -Proxy http://proxy.myLA.local:8080 -ProxyCredential $cred }"

.EXAMPLE
  # PowerShell 7+ (pwsh) with proxy and custom timeout
  pwsh -NoProfile -File ./api_credentials_smoke_test.ps1 `
    -Proxy http://proxy.myLA.local:8080 -ProxyUseDefaultCredentials -ApiTimeout 45

# If your org sets a system proxy (PAC or manual), the script records .NET DefaultWebProxy in diagnostics
# Passing -Proxy makes proxy explicit for both token and POST calls
#>


[CmdletBinding()]
param(
  [ValidateRange(5,120)] [int]$ApiTimeout = 30,

  # --- Optional explicit proxy wiring ---
  [string]$Proxy,                       # e.g. http://proxy.myLA:8080
  [switch]$ProxyUseDefaultCredentials,  # use machine/AD account for the proxy
  [PSCredential]$ProxyCredential        # or pass an explicit PSCredential
)

$timeoutSec = $ApiTimeout

$VERSION = '0.4.4' # bumped from 3.0 to align with main script
Write-Host ("CSC API staging build: v{0}" -f $VERSION)

# Some LA users may need to temporarily alter session PShell permissions 
# Get-ExecutionPolicy -List 
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser

# ----------- LA DfE Config START -----------
# REQUIRED, replace the details in quotes below with your LA's credentials as supplied by DfE
# from https://pp-find-and-use-an-api.education.gov.uk/ (once logged in), transfer the following details into the quotes:

$api_endpoint = "https://pp-api.education.gov.uk/children-in-social-care-data-receiver-test/1" # 'Base URL' - Shouldn't need to change

# From the 'Native OAuth Application-flow' block
$client_id       = "OAUTH_CLIENT_ID_CODE"                # 'OAuth Client ID'
$client_secret   = "NATIVE_OAUTH_PRIMARY_KEY_CODE"       # 'Native OAuth Application-flow' - 'Primary key' or 'Secondary key'
$scope           = "OAUTH_SCOPE_LINK"                    # 'OAuth Scope'
$token_endpoint  = "OAUTH_TOKEN_ENDPOINT"                # From the 'Native OAuth Application-flow' block - 'OAuth token endpoint'

# From 'subscription key' block
$supplier_key    = "SUBSCRIPTION_PRIMARY_KEY_CODE"       # From the 'subscription key' block - 'Primary key' or 'Secondary key'
# ----------- LA DfE Config END -----------


# ----------- LA Internal Config START -----------
$la_code         = "000" # Change to your 3 digit LA code(within quotes)
$la_proxy = $null # LA default proxy ($null or '' disables)
# ----------- LA Internal Config END -----------




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
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 # force TLS 1.2 for AAD and API
[System.Net.ServicePointManager]::Expect100Continue = $false # avoid extra round trip on POST


# ---- Proxy auto-defaults + align .NET default proxy ---- 

# Default proxy IF caller did not pass -Proxy
if (-not $PSBoundParameters.ContainsKey('Proxy') -or [string]::IsNullOrWhiteSpace($Proxy)) {
  if ($la_proxy) { $Proxy = $la_proxy } # Pass -Proxy at run time to override anything set in $la_proxy
}
# Default to current Windows logon for NTLM IF caller didnt choose a creds mode
if ($Proxy -and -not $PSBoundParameters.ContainsKey('ProxyUseDefaultCredentials') -and -not $PSBoundParameters.ContainsKey('ProxyCredential')) {
  $ProxyUseDefaultCredentials = $true
}

# Align .NET's DefaultWebProxy so any HTTP calls not passing -Proxy still use same settings
try {
  if ($Proxy) {
    # Use explicit proxy (or default above) for all .NET web requests also
    $wp = New-Object System.Net.WebProxy($Proxy, $true)
    if ($ProxyUseDefaultCredentials) {
      $wp.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    } elseif ($ProxyCredential) {
      # IMPORTANT: convert PSCredential to NetworkCredential for WebProxy
      $wp.Credentials = $ProxyCredential.GetNetworkCredential()
    }
    [System.Net.WebRequest]::DefaultWebProxy = $wp
  } else {
    # No explicit proxy- keep machine-wide defaults but force NTLM with current user IF creds are empty
    $def = [System.Net.WebRequest]::DefaultWebProxy
    if ($def -and -not $def.Credentials) {
      $def.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    }
  }
} catch { }
# -----------------------------------------------------------------------------------------------



# ----------- Build proxy splat -----------
# If -Proxy supplied but no creds flags, default to -ProxyUseDefaultCredentials.
$ProxyArgs = @{}
if ($Proxy) {
  $ProxyArgs['Proxy'] = $Proxy

  if ($ProxyCredential) {
    $ProxyArgs['ProxyCredential'] = $ProxyCredential
  } elseif ($ProxyUseDefaultCredentials -or -not $PSBoundParameters.ContainsKey('ProxyUseDefaultCredentials')) {
    # default to machine creds when no explicit choice made
    $ProxyArgs['ProxyUseDefaultCredentials'] = $true
  }
  Write-Host ("Proxy enabled: {0}  (DefaultCreds={1}, ExplicitCreds={2})" -f `
      $Proxy, ($ProxyArgs.ContainsKey('ProxyUseDefaultCredentials')), ($ProxyArgs.ContainsKey('ProxyCredential'))) -ForegroundColor DarkGray
} else {
  Write-Host "Proxy disabled (no -Proxy provided)." -ForegroundColor DarkGray
}


# ----------- Utils -----------
function Describe-Code([int]$c) {
  switch ($c) {
    204 { "No content (204)" }
    400 { "Malformed payload (400 BadRequest)" }
    401 { "Invalid token (401 Unauthorised)" }
    403 { "Forbidden / access disallowed (403)" }
    405 { "Method not allowed (405)" }
    408 { "Request timeout (408) - network/WAF/proxy" }
    413 { "Payload too large (413)" }
    415 { "Unsupported media type (415)" }
    429 { "Rate limited (429)" }
    500 { "Internal server error (500)" }
    502 { "Bad gateway (502) - upstream proxy/gateway" }
    503 { "Service unavailable (503)" }
    504 { "Gateway timeout (504) - upstream path issue" }
    default { try { ([System.Net.HttpStatusCode]$c).ToString() } catch { "Other/Unexpected ($c)" } }
  }
}


function Describe-WebExceptionStatus($status) {
  switch ($status) {
    'NameResolutionFailure'      { 'DNS resolution failed (sender-side or proxy DNS)' }
    'ConnectFailure'             { 'TCP connect failed (firewall/blocked port)' }
    'ConnectionClosed'           { 'Connection closed prematurely' }
    'ReceiveFailure'             { 'Receive failed (proxy/WAF/SSL inspection?)' }
    'SendFailure'                { 'Send failed (MTU/proxy/SSL inspection?)' }
    'Timeout'                    { 'Connection/request timed out (network/WAF)' }
    'TrustFailure'               { 'Certificate trust failed' }
    'SecureChannelFailure'       { 'TLS handshake failed (protocol/cipher/inspection)' }
    'ProxyNameResolutionFailure' { 'Proxy DNS failed' }
    'ProxyAuthenticationRequired'{ 'Proxy requires authentication (407)' }
    default { [string]$status }
  }
}

function Get-OAuthToken {
  param(
    [string]$TokenUrl, [string]$ClientId, [string]$ClientSecret, [string]$Scope,
    [hashtable]$ProxyArgs
  )

  # PowerShell form-encode hashtable
  $form = @{
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = $Scope
    grant_type    = 'client_credentials'
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $resp = Invoke-RestMethod -Uri $TokenUrl -Method Post `
              -Body $form `
              -ContentType "application/x-www-form-urlencoded" `
              @ProxyArgs `
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
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [hashtable]$ProxyArgs
  )

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
    ExplicitProxy   = if ($ProxyArgs -and $ProxyArgs.Proxy) { $ProxyArgs.Proxy } else { $null }
    ExplicitProxyMode = if ($ProxyArgs -and $ProxyArgs.Proxy) {
      if ($ProxyArgs.ContainsKey('ProxyCredential')) { 'ExplicitCreds' }
      elseif ($ProxyArgs.ContainsKey('ProxyUseDefaultCredentials')) { 'DefaultCreds' }
      else { 'NoCredFlags' }
    } else { $null }
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
      if ($line) {
        $info.ProxyWinHttp = ($line -join " | ")
        _p ("Proxy : {0}" -f $info.ProxyWinHttp)
      }
    }
  } catch {}

    # TCP + TLS (honour .NET proxy)
    $def = $null; $puri = $null; $bypass = $true
    try {
      # Pull whatever proxy .NET defaults (IE/WinHTTP/Env depending on machine config)
      $def = [System.Net.WebRequest]::DefaultWebProxy
      if ($def) {
        # Ask proxy object what URL would actually send request to
        # (returns proxy URL if proxy applies; otherwise returns original URL)
        $puri    = $def.GetProxy($uri)
        # Check if proxy rules say bypass (i.e., go direct) for URI
        $bypass  = $def.IsBypassed($uri)
      }
      # Record what proxy .NET resolved (string form) and whether bypassing
      $info.ProxyDotNet  = ($puri -as [string])
      $info.ProxyBypass  = $bypass
      if ($info.ProxyDotNet) {
        _p ("Proxy(.NET): {0}  (bypass={1})" -f $info.ProxyDotNet, $info.ProxyBypass)
      }
    } catch { }

    try {
      # Decide if should actually use proxy tunnel:
      #  - we have default proxy object
      #  - we are NOT bypassing target
      #  - we have proxy URI
      #  - and it’s HTTP proxy (CONNECT tunneling below assumes 'http' scheme)
      $useProxy = ($def -and -not $bypass -and $puri -and $puri.Scheme -eq 'http')

      if ($useProxy) {
        # --- PROXY PATH: open TCP socket to proxy + issue HTTP CONNECT ---

        # TCP connect to proxy endpoint
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($puri.Host, $puri.Port)

        # Get raw network stream for read/write
        $net = $tcp.GetStream()
        $sw  = New-Object System.IO.StreamWriter($net); $sw.NewLine="`r`n"; $sw.AutoFlush=$true
        $sr  = New-Object System.IO.StreamReader($net)

        # Ask proxy to establish tunnel to target host:port
        $sw.WriteLine(("CONNECT {0}:{1} HTTP/1.1" -f $targetHost, $targetPort))
        $sw.WriteLine(("Host: {0}:{1}" -f $targetHost, $targetPort))
        $sw.WriteLine("Proxy-Connection: Keep-Alive")
        $sw.WriteLine()  # blank line terminates HTTP headers

        # Read status line back from proxy
        $status = $sr.ReadLine()
        if ($status -notmatch '^HTTP/1\.\d 200') { throw "Proxy CONNECT failed: $status" }

        # Consume rest of proxy response headers
        while (($line = $sr.ReadLine()) -and $line -ne '') { }

        # TCP tunnel via proxy success?
        $info.Tcp = ("Proxy tunnel OK via {0}:{1}" -f $puri.Host, $puri.Port)
        _p ("TCP   : {0}" -f $info.Tcp)

        # layer TLS on top of established tunnel (SSL over CONNECTed stream)
        $script:__sslErrors = [System.Net.Security.SslPolicyErrors]::None
        $ssl = New-Object System.Net.Security.SslStream(
                $net, $false,
                { param($s,$cert,$chain,$errors) $script:__sslErrors = $errors; $true } # capture policy errors, allow continue
              )
        $ssl.AuthenticateAsClient($targetHost)  # SNI/hostname for certificate validation

        # get TLS dets: negotiated protocol and peer cert/issuer
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
        $info.TlsProtocol     = $ssl.SslProtocol
        $info.TlsCert         = $cert.Subject
        $info.TlsIssuer       = $cert.Issuer
        $info.TlsPolicyErrors = $script:__sslErrors

        _p ("TLS   : OK ({0})  Cert: {1}  Issuer: {2}" -f $info.TlsProtocol, $info.TlsCert, $info.TlsIssuer)
        if ($script:__sslErrors -ne [System.Net.Security.SslPolicyErrors]::None) {
          _p ("TLS   : Policy errors: {0}" -f $script:__sslErrors) Yellow
        }

        # clean up (only probe TLS; no HTTP over TLS sent here)
        $ssl.Close(); $net.Close(); $tcp.Close()
      }
      else {
        # --- DIRECT PATH: connect straight to target host:port without proxy ---

        # TCP connect direct with 3s timeout using Begin/EndConnect
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($targetHost, $targetPort, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { $tcp.Close(); throw "TCP connect timeout" }
        $tcp.EndConnect($iar)

        # did we get direct TCP success
        $info.Tcp = ("Connected to {0}:{1}" -f $targetHost, $targetPort)
        _p ("TCP   : {0}" -f $info.Tcp)

        # do TLS handshake directly to origin server
        $script:__sslErrors = [System.Net.Security.SslPolicyErrors]::None
        $ssl = New-Object System.Net.Security.SslStream(
                $tcp.GetStream(), $false,
                { param($s,$cert,$chain,$errors) $script:__sslErrors = $errors; $true }
              )
        $ssl.AuthenticateAsClient($targetHost)

        # get TLS dets as above
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
        $info.TlsProtocol     = $ssl.SslProtocol
        $info.TlsCert         = $cert.Subject
        $info.TlsIssuer       = $cert.Issuer
        $info.TlsPolicyErrors = $script:__sslErrors

        _p ("TLS   : OK ({0})  Cert: {1}  Issuer: {2}" -f $info.TlsProtocol, $info.TlsCert, $info.TlsIssuer)
        if ($script:__sslErrors -ne [System.Net.Security.SslPolicyErrors]::None) {
          _p ("TLS   : Policy errors: {0}" -f $script:__sslErrors) Yellow
        }

        # Clean up
        $ssl.Close(); $tcp.Close()
      }
    }
    catch {
      # exception in either path: record note and show failure
      $info.Note = "TLS fail: " + $_.Exception.Message
      _p ("TCP/TLS: FAILED ({0})" -f $_.Exception.Message) Yellow
    }


  # HEAD probes (use same proxy args if given)
  if ($DIAG_HTTP_PROBE) {
    try {
      $rootUrl = "{0}://{1}/" -f $uri.Scheme,$uri.Host
      $rootResp = Invoke-WebRequest -Uri $rootUrl -Method Head -UseBasicParsing -TimeoutSec 10 @ProxyArgs -ErrorAction Stop
      $info.HeadRoot = ("{0} -> {1}" -f $rootUrl,$rootResp.StatusCode); _p ("HTTP  : HEAD {0}" -f $info.HeadRoot)
    } catch { $info.HeadRoot = ("{0} FAILED ({1})" -f $rootUrl,$_.Exception.Message); _p ("HTTP  : HEAD {0}" -f $info.HeadRoot) Yellow }
    try {
      $pathResp = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 10 @ProxyArgs -ErrorAction Stop
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
$token = Get-OAuthToken -TokenUrl $token_endpoint -ClientId $client_id -ClientSecret $client_secret -Scope $scope -ProxyArgs $ProxyArgs

# bail early (and run diags) if token failed
$headers    = $null
$code       = $null
$desc       = $null
$requestId  = $null
$swCall     = [System.Diagnostics.Stopwatch]::StartNew()
$bodyBytes  = $null   # for reporting only
$payloadLen = 0       # number to print later
$preview    = ""      # short preview to print later

if (-not $token) {
  Write-Host "Cannot continue without token." -ForegroundColor Red
  $swCall.Stop()
  $code = 401
  $desc = Describe-Code 401
  if ($ENABLE_DIAGNOSTICS -and ($DIAG_ON_HTTP_CODES -contains 401)) {
    $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint -ProxyArgs $ProxyArgs
  }
}
else {
    # ---------- Build smoke-test [] ARRAY payload (ordered + better preview) ----------
    $la_code_str = '{0:D3}' -f [int]$la_code
    $childId     = "Fake1234$la_code_str"

    $payload = @(
      [ordered]@{
        la_child_id   = $childId                       
        mis_child_id  = "MIS$la_code_str"
        child_details = [ordered]@{
          unique_pupil_number = "A123456789012"
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

    # JSON for HTTP body
    $body = ConvertTo-Json -InputObject $payload -Depth 10 -Compress

    # only for console preview (keeps [ordered]@{})
    $bodyPretty = ConvertTo-Json -InputObject $payload -Depth 10

    # HTTP body UTF-8 (no BOM)
    $utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
    $bodyBytes  = $utf8NoBom.GetBytes($body)

    # for output/sanity checks
    $payloadLen = if ($bodyBytes) { $bodyBytes.Length } else { 0 }

    # head+tail with snip marker or full pretty JSON
    $PREVIEW_LIMIT = 3000
    if ($bodyPretty.Length -le $PREVIEW_LIMIT) {
      $preview = $bodyPretty
    } else {
      $preview = $bodyPretty.Substring(0, [Math]::Min(1500, $bodyPretty.Length)) +
                 "`n... SNIP (preview truncated) ...`n" +
                 $bodyPretty.Substring([Math]::Max(0, $bodyPretty.Length - 1500))
    }

    ## DEBUG: show _ids 
    #Write-Host ("la_child_id (first rec): {0}" -f $payload[0].la_child_id) -ForegroundColor DarkCyan
    #Write-Host ("mis_child_id (first rec): {0}" -f $payload[0].mis_child_id) -ForegroundColor DarkCyan


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
              -UseBasicParsing -TimeoutSec $timeoutSec `
              @ProxyArgs `
              -ErrorAction Stop

    $swCall.Stop()
    # success path (no exception)
    $code = $resp.StatusCode
    $desc = Describe-Code $code

    # run diags even on success IF code in allow-list (e.g., 204)
    if ($ENABLE_DIAGNOSTICS -and ($DIAG_ON_HTTP_CODES -contains [int]$code)) {
      $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint -ProxyArgs $ProxyArgs
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
        $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint -ProxyArgs $ProxyArgs
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
        $script:DiagData = Get-ConnectivityDiagnostics -Url $endpoint -ProxyArgs $ProxyArgs
      }
    }
  }
}  # end else(token OK)


# ----------- BASIC ENV DETS FOR REF -----------
# Minimal host env details (PS 5.0-safe)
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
if ($ProxyArgs -and $ProxyArgs.Proxy) {
  $pmode = if ($ProxyArgs.ContainsKey('ProxyCredential')) { 'ExplicitCreds' } elseif ($ProxyArgs.ContainsKey('ProxyUseDefaultCredentials')) { 'DefaultCreds' } else { 'NoCredFlags' }
  Write-Host ("Proxy Used         : {0} ({1})" -f $ProxyArgs.Proxy, $pmode)
}
Write-Host ("Total runtime (s)  : {0:N2}" -f $scriptTotalSeconds)

# exit code preview
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
  if ($script:DiagData.ExplicitProxy)   { Write-Host ("Explicit Proxy    : {0} Mode={1}" -f $script:DiagData.ExplicitProxy, $script:DiagData.ExplicitProxyMode) }
  if ($script:DiagData.HeadRoot)        { Write-Host ("HEAD Root         : {0}" -f $script:DiagData.HeadRoot) }
  if ($script:DiagData.HeadPath)        { Write-Host ("HEAD Endpoint     : {0}" -f $script:DiagData.HeadPath) }
  if ($script:DiagData.Note)            { Write-Host ("Diag Note         : {0}" -f $script:DiagData.Note) }
}
Write-Host "===== END D2I COPY BLOCK =====" -ForegroundColor Cyan
Write-Host ""

# CI / calling shell exit
if ($null -eq $exitCode) { $exitCode = 1 }
exit $exitCode
