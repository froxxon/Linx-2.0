# Security Review – RestPSWrapper

Overall, the wrapper has a solid security foundation: mandatory authentication (`[Authorize]`), HMAC-SHA256 request signing, CSRF token enforcement with timing-safe comparison, HSTS, CSP nonces, and circuit-breaking. Several issues remain that require attention.

---

## 🔴 HIGH – Rate Limiter IP Spoofing

**File:** `Middleware/RateLimitingMiddleware.cs` – `GetClientIpAddress()`

The middleware reads `X-Forwarded-For` directly from the raw request headers instead of using `context.Connection.RemoteIpAddress`, which has already been normalised by `UseForwardedHeaders()`:

```csharp
// Current – reads raw header, attacker-controlled
var forwardedFor = context.Request.Headers["X-Forwarded-For"].FirstOrDefault();
```

`UseForwardedHeaders()` runs first and sets `context.Connection.RemoteIpAddress` to the verified real client IP. By re-parsing the raw header, an attacker from outside the trusted network can supply any value (e.g., `X-Forwarded-For: 127.0.0.1`) and bypass rate limits entirely.

**Fix:** Replace the IP extraction with `context.Connection.RemoteIpAddress?.ToString()` directly, since `UseForwardedHeaders()` has already done the verification.

---

## 🔴 HIGH – Backend Response Headers Forwarded Unfiltered

**File:** `Controllers/ProxyController.cs` – lines 98–115

All headers returned by the PowerShell backend are proxied to the client without a whitelist:

```csharp
Response.Headers[header.Key] = header.Value;
```

This allows the PS backend to silently override `Content-Security-Policy`, `Strict-Transport-Security`, `X-Frame-Options`, and `Set-Cookie` headers that the security middleware carefully sets. A compromised or misconfigured PS script can therefore undo all wrapper-level security headers.

**Fix:** Maintain a whitelist of headers allowed to pass through from the backend, and/or explicitly remove any security-sensitive header names from the backend response before forwarding.

---

## 🔴 HIGH – Any Authenticated User Can Shut Down the PS Backend

**File:** `Linx/RestPSModule/RestPSCustomModule.psm1` – `Start-RestPSListener`

The PS backend handles a `/EndPoint/Shutdown` GET request by setting `$script:Status = $false` and stopping the listener loop. The C# wrapper has no route exclusion for this path, so any authenticated user can call `GET /EndPoint/Shutdown` and crash the PowerShell backend (DoS).

```powershell
if ($RequestURL -match '/EndPoint/Shutdown$') {
    $script:Status = $false  # Terminates the listener
}
```

**Fix:** Either remove the shutdown endpoint entirely (the C# application lifecycle should be managed externally), or restrict it to a role/group claim in the C# `ProxyController` before forwarding.

---

## 🟡 MEDIUM – Session ID Accepted Without Validation (Session Fixation)

**File:** `Middleware/SecurityMiddleware.cs` – `GetOrCreateSessionId()`

If the `SessionId` cookie is present, its value is used as-is without any format validation, length check, or binding to the authenticated user:

```csharp
if (context.Request.Cookies.TryGetValue("SessionId", out var sessionId))
    return sessionId;
```

An attacker can pre-set the `SessionId` cookie to an arbitrary value (session fixation), then present valid CSRF tokens for that session ID. There is also no max-length check, so a very long cookie value contributes to memory pressure in the `ConcurrentDictionary`.

**Fix:** Validate that the session ID is a well-formed GUID (`Guid.TryParse`). Additionally, consider binding the session ID to the authenticated username (e.g., include the username hash in the session ID, or store a username alongside the session entry and verify it on every request).

---

## 🟡 MEDIUM – Weak Default CSP in `appsettings.json`

**File:** `appsettings.json` (line 16)

```json
"HTMLContentSecurityPolicy": "block-all-mixed-content; base-uri 'none'; object-src 'none';"
```

This policy omits `default-src`, `script-src`, and `style-src`. Without these, browsers fall back to `*` for script and style sources, allowing inline scripts from any origin and defeating XSS protection. The `ScriptVariablesConfig.cs` default is stronger, but `appsettings.json` overrides it at runtime.

**Fix:** Use a policy that includes at minimum `default-src 'self'; script-src 'self' 'nonce-{nonce}'; style-src 'self';`.

---

## 🟡 MEDIUM – `RequestSizeLimitMiddleware` Bypassed by Chunked Encoding

**File:** `Middleware/RequestSizeLimitMiddleware.cs`

The size check only triggers when `ContentLength.HasValue` is true:

```csharp
context.Request.ContentLength.HasValue &&
_maxRequestBodySize > 0 &&
context.Request.ContentLength > _maxRequestBodySize
```

A chunked-encoded request (`Transfer-Encoding: chunked`) has no `Content-Length` header, so it bypasses this middleware entirely. The body is later fully buffered in the controller (`Request.EnableBuffering()`), potentially exhausting server memory.

**Fix:** Use `IHttpMaxRequestBodySizeFeature` to enforce the limit at the framework level for all requests, or read and limit the actual body stream rather than relying on the declared `Content-Length`.

---

## 🟡 MEDIUM – PS Backend Runs Anonymous / No Network-Level Auth

**File:** `Linx/RestPSModule/RestPSCustomModule.psm1` – `Start-RestPSListener`

```powershell
$listener.AuthenticationSchemes = 'Anonymous'
$listener.UnsafeConnectionNtlmAuthentication = $true
```

The PS backend uses anonymous authentication, relying entirely on the C# wrapper for security. If the PS backend port (default: 8080) is reachable from the network (not strictly loopback), any client can call it without authentication. `UnsafeConnectionNtlmAuthentication = $true` is also a concern if the listener is ever exposed—it allows NTLM credential relay on non-SSL connections.

**Fix:** Bind the PS backend listener strictly to `localhost` (127.0.0.1 only). Verify that the OS firewall blocks external access to port 8080. Consider using the `X-Request-Signature` header (already generated by the wrapper) to reject requests that did not originate from the C# wrapper.

---

## 🟡 MEDIUM – Security Headers Not Applied to Auth Failure Responses

**File:** `Program.cs` – middleware order

`SecurityMiddleware` (which sets CSP, X-Frame-Options, HSTS, etc.) runs **after** `UseAuthentication()` and `UseAuthorization()`. A 401/403 response generated by the auth layer is sent to the client without any security headers. An attacker receiving an auth-failure response gets a page with no CSP, no X-Frame-Options, and no HSTS.

**Fix:** Move `SecurityMiddleware` (at minimum its header-setting portion) to before `UseAuthentication()`, or duplicate the header-application step in the exception/error handling pipeline.

---

## 🟠 LOW – `AllowedHosts: "*"` Allows Any Host Header

**File:** `appsettings.json` (line 8)

```json
"AllowedHosts": "*"
```

This disables Host header validation, which can facilitate HTTP Host header injection attacks and open redirect in some scenarios.

**Fix:** Set `AllowedHosts` to the specific hostname(s) the service will serve (e.g., `"AllowedHosts": "app.example.com"`).

---

## 🟠 LOW – CSRF Endpoint Leaks `expiresIn` Hardcoded Value

**File:** `Controllers/CsrfController.cs` – `GetToken()`

```csharp
expiresIn = "3600 seconds",
```

This value is hardcoded and will not match if `CsrfTokenExpirationSeconds` is changed in configuration. Minor informational inconsistency; fix by using `_csrfTokenService` or config to return the actual configured value.

---

## 🟠 LOW – Request Body Always Re-Typed as `application/json`

**File:** `Services/PowerShellProxyService.cs`

```csharp
request.Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");
```

The original request's `Content-Type` is ignored; all bodies are forwarded as `application/json`. If the PS backend validates Content-Type, this works, but it prevents future support for multipart or other types.

---

## Summary Table

| Severity | Issue |
|---|---|
| 🔴 HIGH | Rate limiter IP spoofing via raw `X-Forwarded-For` |
| 🔴 HIGH | Backend response headers forwarded without whitelist |
| 🔴 HIGH | Any authenticated user can shut down the PS backend |
| 🟡 MEDIUM | Session fixation / no session ID validation |
| 🟡 MEDIUM | Weak CSP in `appsettings.json` (no `default-src`, `script-src`) |
| 🟡 MEDIUM | `RequestSizeLimitMiddleware` bypassed by chunked encoding |
| 🟡 MEDIUM | PS backend accessible without auth if not strictly loopback-bound |
| 🟡 MEDIUM | Security headers missing from auth failure responses |
| 🟠 LOW | `AllowedHosts: "*"` |
| 🟠 LOW | Hardcoded `expiresIn` in CSRF token response |
| 🟠 LOW | Request body always re-typed as `application/json` |
