
# D2I Admin - Proxy Support in PowerShell API Scripts (PS 5.1)

# Proxy Support in PowerShell API Scripts (PS 5.1)

How to/notes towards adding **optional** LA proxy support to both **main** and **smoke-test** CSC API scripts.

Keeps behaviour unchanged when no proxy is supplied, but lets LAs that require an explicit proxy (proxy auth) pass those details

---

## Why this may be needed

- **Explicit proxies with auth**: many LAs require outbound HTTPS to go via a proxy (often NTLM or Kerberos). Without `-Proxy` plus credentials you can hit `407` or timeouts before token or API call
- **Transparent, WPAD, allow lists**: other environments do one of:
  - transparent proxying - no client config needed
  - PAC or machine WinHTTP proxy - .NET or PowerShell already knows proxy
  - allow listed endpoints - traffic to token or API hosts bypasses proxy
- Result: some LAs do not need to change scripts; others must pass proxy options

---

## What to add (summary)

1. **Parameters**: `-Proxy`, `-ProxyUseDefaultCredentials`, `-ProxyCredential`
2. **Optional site default**: `$la_proxy = 'http://proxy.myLA.local:8080'` which is used only if caller does not pass `-Proxy`
3. **Helper**: `Get-ProxySplat` returns a hashtable of proxy args for splatting
4. **Align .NET default proxy**: set `[System.Net.WebRequest]::DefaultWebProxy` so any HTTP paths you forget still use the same proxy and credentials
5. Wire proxy into **token** call and **API POST** calls

Everything is **optional**; if you do not pass a proxy, script behaves as before

> Tip: do not set both `-ProxyUseDefaultCredentials` and `-ProxyCredential` at the same time

---

## Update all API POST calls

### Smoke-test script (single POST)

```powershell
$proxy = Get-ProxySplat
$response = Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers `
            -ContentType "application/json" -Body $bodyBytes `
            -UseBasicParsing -TimeoutSec $ApiTimeout @proxy -ErrorAction Stop
```

---

## How to run

### Use proxy with current Windows logon (NTLM or Kerberos)

```powershell
.\phase_1_api_payload.ps1 -Phase full `
  -Proxy "http://proxy.myLA.local:8080" `
  -ProxyUseDefaultCredentials
```

### Use proxy with explicit credentials

```powershell
$cred = Get-Credential  # DOMAIN\user + password
.\phase_1_api_payload.ps1 -Phase deltas `
  -Proxy "http://proxy.myLA.local:8080" `
  -ProxyCredential $cred
```

### Use optional site default

Add your LA proxy once near the top of the script

```powershell
$la_proxy = 'http://proxy.myLA.local:8080'
```

CLI passing `-Proxy` overrides in script defined `$la_proxy`

### No proxy

```powershell
.\phase_1_api_payload.ps1 -Phase full
```

---

## Tips

- **401 on token**: wrong AAD scope or client secret expired or proxy interception. Ensure token request also uses the proxy
- **407 proxy authentication required**: pass `-ProxyUseDefaultCredentials` or `-ProxyCredential`
- **403 from API**: token audience or scope mismatch or WAF rules. Include clean headers and ensure payload matches schema
- **Timeouts or TLS errors**: proxy SSL inspection or blocked CONNECT. Check `netsh winhttp show proxy` and the script diagnostics
- **Mixed config**: do not set both `-ProxyUseDefaultCredentials` and `-ProxyCredential`
- Save scripts as UTF-8 with BOM in VS Code if you see odd characters

---

## Notes

- PS 5.1 uses .NET HttpWebRequest under the hood. `-Proxy` on `Invoke-*` is explicit. `DefaultWebProxy` is fallback
- If your LA manages WinHTTP proxy via GPO, you may not need to pass `-Proxy` at all. The .NET default proxy path can already work
