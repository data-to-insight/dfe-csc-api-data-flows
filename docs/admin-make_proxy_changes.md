
# Enable Proxy Support in PowerShell API Scripts (PS 5.1)

How to/notes towards adding **optional** corporate proxy support to both **main** and **smoke-test** CSC API scripts.

Keeps behaviour unchanged when no proxy is supplied, but lets LAs that require an explicit proxy (proxy auth) pass those details. Most likely i will be implementing this, but in the short term these notes provided in case LAs need them directly. 

---

## Why this may be needed 

- **Explicit proxies with auth**: Many organisations require outbound HTTPS to go via a proxy (often NTLM/Kerberos). Without `-Proxy` + creds you can hit `407` or timeouts before token/API call.
- **Transparent/WPAD/allowlists**: Other environments do one of:
  - *Transparent proxying* — no client config needed
  - *WPAD/PAC or machine WinHTTP proxy* — .NET/PowerShell already knows proxy
  - *Allow-listed endpoints* — traffic to token/API hosts bypasses proxy
- Result: some LAs dont needd to change scripts; others must pass proxy options

---

## What to add (summary)

1. **New parameters**: `-Proxy`, `-ProxyUseDefaultCreds`, `-ProxyCredential`
2. **Helper** `Add-ProxyParams` to inject proxy options into any `Invoke-*` call
3. (Optional) **DefaultWebProxy** set once — useful for bits you forget to wire
4. Wire proxy into **token** call and **API POST** calls (incl. `Send-ApiBatch`)

Everything is **optional**; if you don’t pass a proxy, script behaves as before

---

## Add parameters

Put this in `param(...)` block (nr top of script)

```powershell
param(
  [ValidateSet('full','deltas')] [string]$Phase = 'full',
  [switch]$InternalTest,
  [switch]$UseTestRecord,
  [int]$BatchSize = 100,
  [int]$ApiTimeout = 30,

  # proxy (optional)
  [string]$Proxy,                    # e.g. http://proxy.company.local:8080
  [switch]$ProxyUseDefaultCreds,     # use current logon creds
  [pscredential]$ProxyCredential     # or pass explicit creds
)
```

> Tip: don’t set both `-ProxyUseDefaultCreds` **and** `-ProxyCredential` at same time (might cause conflict here)

---

## inject proxy options

Add this. It gets re‑used for token + data calls

```powershell
function Add-ProxyParams {
  param([hashtable]$h)
  if ($Proxy) {
    $h.Proxy = $Proxy
    if     ($ProxyUseDefaultCreds) { $h.ProxyUseDefaultCredentials = $true }
    elseif ($ProxyCredential)      { $h.ProxyCredential = $ProxyCredential }
  }
  return $h
}
```

---

## (optional) Set global default proxy

Helps diagnostic and stray calls you forget to wire.

```powershell
if ($Proxy) {
  $wp = New-Object System.Net.WebProxy($Proxy)
  if     ($ProxyUseDefaultCreds) { $wp.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials }
  elseif ($ProxyCredential)      { $wp.Credentials = $ProxyCredential }
  [System.Net.WebRequest]::DefaultWebProxy = $wp
}
```

---

## Update token function

Ensure **token** request uses proxy. Eg for AAD v2 (`scope`) and v1 (`resource`) support:

```powershell
function Get-OAuthToken {
  param(
    [Parameter(Mandatory=$true)][string]$TokenUrl,
    [Parameter(Mandatory=$true)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$ClientSecret,
    [string]$Scope,     # v2, e.g. api://GUID/.default  (we'll append /.default if missing)
    [string]$Resource   # v1, e.g. https://resource-app-id-uri
  )

  $isV2 = ($TokenUrl -match '/v2\.0/')
  if ($isV2) {
    if ($Scope -and ($Scope -notmatch '\.default$')) { $Scope = "$Scope/.default" }
    if (-not $Scope) { Write-Host "Token cfg needs v2 scope" -ForegroundColor Yellow; return $null }
  } else {
    if (-not $Resource -and $Scope) { $Resource = $Scope }
    if (-not $Resource) { Write-Host "Token cfg needs v1 resource" -ForegroundColor Yellow; return $null }
  }

  $pairs = @(
    "grant_type=client_credentials",
    "client_id=$([uri]::EscapeDataString($ClientId))",
    "client_secret=$([uri]::EscapeDataString($ClientSecret))"
  )
  if ($isV2) { $pairs += "scope=$([uri]::EscapeDataString($Scope))" }
  else       { $pairs += "resource=$([uri]::EscapeDataString($Resource))" }
  $form = ($pairs -join '&')

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $irm = @{
      Uri         = $TokenUrl
      Method      = 'Post'
      Body        = $form
      ContentType = 'application/x-www-form-urlencoded'
      ErrorAction = 'Stop'
    }
    Add-ProxyParams -h $irm | Out-Null
    $resp = Invoke-RestMethod @irm
    $sw.Stop()
    Write-Host ("Token fetched in {0:N2}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    return $resp.access_token
  } catch {
    $sw.Stop()
    Write-Host ("Token request failed after {0:N2}s: {1}" -f $sw.Elapsed.TotalSeconds, $_.Exception.Message) -ForegroundColor Red
    return $null
  }
}
```

---

## Update **all** API POST calls

### Smoke-test script (single POST)
```powershell
$irm = @{
  Uri         = $endpoint
  Method      = 'Post'
  Headers     = $headers
  Body        = $bodyBytes   # or str body
  ContentType = 'application/json; charset=utf-8'
  TimeoutSec  = $ApiTimeout
  ErrorAction = 'Stop'
}
Add-ProxyParams -h $irm | Out-Null
$response = Invoke-WebRequest @irm
```

### Main script (`Send-ApiBatch`)

- **Function signature** gains proxy args:
```powershell
param(
  [array]$batch, [string]$endpoint, [hashtable]$headers,
  [string]$connectionString, [string]$tableName,
  [ref]$FailedResponses, [string]$FinalJsonPayload,
  [ref]$CumulativeDbWriteTime,
  [int]$maxRetries = 3, [int]$timeout = 30,
  [string]$Proxy, [switch]$ProxyUseDefaultCreds, [pscredential]$ProxyCredential
)
```

- **Use splatting** inside:
```powershell
$irm = @{
  Uri         = $endpoint
  Method      = 'Post'
  Headers     = $headers
  Body        = $FinalJsonPayload
  ContentType = 'application/json'
  TimeoutSec  = $timeout
  ErrorAction = 'Stop'
}
Add-ProxyParams -h $irm | Out-Null
$response = Invoke-RestMethod @irm
```

- **Call-site** passes through proxy options:
```powershell
Send-ApiBatch -batch $batchSlice `
  -endpoint $api_endpoint_with_lacode `
  -headers $headers `
  -connectionString $connectionString `
  -tableName $api_data_staging_table `
  -FailedResponses ([ref]$FailedResponses) `
  -FinalJsonPayload $finalPayload `
  -CumulativeDbWriteTime ([ref]$cumulativeDbWriteTime) `
  -timeout $ApiTimeout `
  -Proxy $Proxy -ProxyUseDefaultCreds:$ProxyUseDefaultCreds -ProxyCredential $ProxyCredential
```

---

## How to run

### Use proxy with current Windows logon (NTLM/Kerberos)
```powershell
.\phase_1_api_payload.ps1 -Phase full `
  -Proxy "http://proxy.company.local:8080" `
  -ProxyUseDefaultCreds
```

### Use proxy with explicit creds
```powershell
$cred = Get-Credential  # DOMAIN\user + password
.\phase_1_api_payload.ps1 -Phase deltas `
  -Proxy "http://proxy.company.local:8080" `
  -ProxyCredential $cred
```

### No proxy (def' behaviour)
```powershell
.\phase_1_api_payload.ps1 -Phase full
```

---

## tips

- **401 on token**: wrong AAD flow (v1 vs v2), wrong `scope`/`resource`, client secret expired, or proxy intercepting/stripping auth - ensure token call also uses the proxy
- **407 Proxy Authentication Required**: pass `-ProxyUseDefaultCreds` (preferred on joined servers running as service accounts) **or** `-ProxyCredential`
- **403 from API**: token audience/scope mismatch, WAF rules - include clean headers (e.g. `Accept: application/json`, tame `User-Agent`), ensure payload matches schema
- **Timeouts / TLS errors**: proxy SSL inspection, blocked CONNECT; check with `netsh winhttp show proxy` and the script’s diagnostics
- **Mixed config**: don’t set both `-ProxyUseDefaultCreds` and `-ProxyCredential`

---

## Notes

- PS 5.1 uses .NET `HttpWebRequest` underneath. `-Proxy` on `Invoke-*` is explicit; `DefaultWebProxy` is fallback
- If your LA manages WinHTTP proxy via GPO, you may not need to pass `-Proxy` at all - the `DefaultWebProxy` path already works

