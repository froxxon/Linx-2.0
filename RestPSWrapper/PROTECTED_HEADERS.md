# Protected Headers Implementation

## Overview
The RestPSWrapper now dynamically protects security headers configured in `appsettings.json` from being overwritten by the PowerShell backend.

## How It Works

### 1. Dynamic Protection
Headers are **automatically protected** based on configuration - no hardcoded list needed:
- Any security header set from `appsettings.json` during the `SecurityMiddleware` pipeline is tracked
- These headers are stored in `HttpContext.Items["ProtectedHeaders"]`
- The `ProxyController` checks this list before applying PowerShell backend headers

### 2. Protected Headers (from appsettings.json)
The following headers are dynamically protected when configured:
- `Cache-Control` - from `HTMLCacheControl`
- `Pragma` - always set to "no-cache"
- `Expires` - always set to "0"
- `Content-Security-Policy` - from `HTMLContentSecurityPolicy`
- `X-Content-Type-Options` - from `HTMLXContentTypeOptions`
- `Content-Language` - from `ContentLanguage`
- `X-Frame-Options` - always set to "DENY"
- `X-Permitted-Cross-Domain-Policies` - always set to "none"
- `Strict-Transport-Security` - calculated from `HstsMaxAgeDays` (HTTPS only)

### 3. Logging
When the PowerShell backend attempts to overwrite a protected header:
```
[Warning] PowerShell backend attempted to overwrite protected header 'Cache-Control'. 
This header is set in appsettings.json and cannot be overwritten. 
Backend value 'public, max-age=3600' was ignored.
```

## Benefits

✅ **Dynamic** - Adapts automatically to configuration changes  
✅ **Secure** - appsettings.json remains the source of truth for security headers  
✅ **Transparent** - Logs warnings when PS backend tries to overwrite protected headers  
✅ **Flexible** - Non-security headers from PS backend are still forwarded normally  

## Example Scenario

### appsettings.json
```json
{
  "ScriptVariables": {
	"HTMLCacheControl": "no-cache, no-store, must-revalidate",
	"HTMLContentSecurityPolicy": "default-src 'self'",
	"ContentLanguage": "sv-SE"
  }
}
```

### PowerShell Backend Response
```powershell
# These headers will be IGNORED (protected):
$response.Headers["Cache-Control"] = "public, max-age=3600"
$response.Headers["Content-Security-Policy"] = "default-src *"

# These headers will be FORWARDED (not protected):
$response.Headers["X-Custom-Header"] = "custom-value"
$response.Headers["X-Request-Id"] = "12345"
```

### Result
- `Cache-Control`: "no-cache, no-store, must-revalidate" (from appsettings.json ✅)
- `Content-Security-Policy`: "default-src 'self'" (from appsettings.json ✅)
- `Content-Language`: "sv-SE" (from appsettings.json ✅)
- `X-Custom-Header`: "custom-value" (from PS backend ✅)
- `X-Request-Id`: "12345" (from PS backend ✅)

## Modified Files
1. `Services/ISecurityHeaderService.cs` - Updated interface to return protected headers
2. `Services/SecurityHeaderService.cs` - Tracks and returns protected header names
3. `Middleware/SecurityMiddleware.cs` - Stores protected headers in HttpContext
4. `Controllers/ProxyController.cs` - Checks protected headers before applying backend headers
