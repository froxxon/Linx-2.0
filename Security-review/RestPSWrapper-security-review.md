# Security Review – RestPSWrapper (Re-evaluated)

This report re-evaluates the previous findings against the current codebase.

---

## ✅ Resolved Since Previous Review

- Rate limiting now uses validated `context.Connection.RemoteIpAddress` instead of raw `X-Forwarded-For`.
- Proxy response handling now blocks backend overrides of protected security headers.
- Session handling now validates `SessionId` as GUID and binds sessions to user context.
- The previously reported `/EndPoint/Shutdown` route is not present in current backend code.
- CSP in `appsettings.json` now includes `default-src 'self'` (previous fallback-to-`*` claim no longer applies).

---

## 🟡 MEDIUM – Request Size Middleware Still Depends on `Content-Length`

**File:** `Middleware/RequestSizeLimitMiddleware.cs`

The middleware only enforces limits when `ContentLength.HasValue` is true, so transfer modes without declared length are not checked by this middleware path.

**Recommendation:** Enforce size limits at server/body-stream level for all request types, not only declared `Content-Length`.

---

## 🟡 MEDIUM – PowerShell Backend Listener Still Anonymous by Default

**File:** `Linx/RestPSModule/RestPSCustomModule.psm1`

```powershell
$listener.AuthenticationSchemes = 'Anonymous'
$listener.UnsafeConnectionNtlmAuthentication = $true
```

If backend exposure is misconfigured beyond localhost/firewall boundaries, requests may bypass wrapper-layer controls.

**Recommendation:** Keep backend loopback-only and add explicit backend-side request authentication (for example signature verification).

---

## 🟡 MEDIUM – Security Headers Are Applied After Auth Middleware

**File:** `Program.cs`

`UseAuthentication()`/`UseAuthorization()` run before `SecurityMiddleware`, so auth-generated 401/403 responses may miss the intended security header set.

**Recommendation:** Apply security headers earlier in the pipeline (or via a dedicated global header middleware that runs before auth responses are generated).

---

## 🟠 LOW – `AllowedHosts` Still Wildcard

**File:** `appsettings.json`

```json
"AllowedHosts": "*"
```

**Recommendation:** Restrict to explicit hostnames in production.

---

## 🟠 LOW – CSRF `expiresIn` Response Field Is Hardcoded

**File:** `Controllers/CsrfController.cs`

`expiresIn` is still returned as a hardcoded string (`"3600 seconds"`) instead of the configured value.

---

## 🟠 LOW – Forwarded Request Body Content-Type Forced to JSON

**File:** `Services/PowerShellProxyService.cs`

Forwarded request bodies are always sent as `application/json`, which can cause content-type confusion for non-JSON payloads.

---

## Summary Table

| Severity | Issue |
|---|---|
| 🟡 MEDIUM | Request size middleware only enforces limits when `Content-Length` is present |
| 🟡 MEDIUM | Backend listener remains anonymous and depends on network isolation |
| 🟡 MEDIUM | Security headers applied after auth middleware |
| 🟠 LOW | `AllowedHosts` wildcard |
| 🟠 LOW | Hardcoded CSRF `expiresIn` response value |
| 🟠 LOW | Request body content-type retyped as `application/json` |
