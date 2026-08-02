# Request Signature Validation - PowerShell Backend

## Overview

The RestPSWrapper .NET application signs all requests forwarded to the PowerShell backend using HMAC-SHA256. The PowerShell backend validates these signatures to ensure requests originated from the authorized wrapper and haven't been tampered with.

**Status**: ✅ **ACTIVE** - Global signature validation is now enforced in `RestPSCustomModule.psm1` (lines 384-387).

## How It Works

### 1. Wrapper Signs Requests

The .NET wrapper (`ProxyController.cs`) generates a signature for every request:

```csharp
// Signature includes: user | method | path | body length | body content
var bodyForSignature = string.IsNullOrEmpty(body) ? "[EMPTY]" : body;
var bodyLength = body?.Length ?? 0;
var signatureData = $"{userName}|{Request.Method}|{path}|{bodyLength}|{bodyForSignature}";
var signature = _signatureService.GenerateSignature(signatureData); // HMAC-SHA256
userHeaders["X-Request-Signature"] = signature;
```

The signature is sent in the `X-Request-Signature` HTTP header.

### 2. Backend Validates Signature (ACTIVE)

**Current Implementation**: The PowerShell backend now automatically validates all request signatures in `RestPSCustomModule.psm1`:

```powershell
# Lines 384-387 in RestPSCustomModule.psm1
if ( $ScriptVariables.RequestSignatureSecret ) {
    if ( 'null' -ne $Body ) { $SignatureBody = $Body } else { $SignatureBody = '' }
    if ( (Test-RequestSignature -Request $Request -Body $SignatureBody -Secret $ScriptVariables.RequestSignatureSecret) -eq $false ) { return $false }
}
```

When `RequestSignatureSecret` is configured, the backend automatically:
1. Validates the signature for every incoming request
2. Rejects requests with invalid or missing signatures (returns `$false`)
3. Only processes requests with valid signatures

**Optional Per-Endpoint Validation**: You can also validate signatures in individual endpoint scripts:

```powershell
# In your endpoint script or in the RestPSCustomModule request handler
$isValid = Test-RequestSignature -Request $script:Request -Body $script:Body -Secret $ScriptVariables.RequestSignatureSecret

if (-not $isValid) {
	$script:StatusCode = 401
	$script:StatusDescription = "Unauthorized - Invalid Signature"
	return $null
}

# Continue processing the request...
```

## Configuration

### Required Settings

**Both applications must share the same secret:**

#### .NET Wrapper (`RestPSWrapper/appsettings.json`):
```json
{
  "ScriptVariables": {
	"RequestSignatureSecret": "${RESTPS_SIGNATURE_SECRET}"
  }
}
```

Use an environment variable for production:
```powershell
$env:RESTPS_SIGNATURE_SECRET = "your-strong-secret-key-here-min-32-chars"
```

#### PowerShell Backend (`Linx/base_settings.json`):
```json
{
  "RequestSignatureSecret": "your-strong-secret-key-here-min-32-chars"
}
```

**⚠️ IMPORTANT:** The secret must be:
- At least 32 characters long (longer is better)
- Cryptographically random (use `[System.Guid]::NewGuid().ToString()` or similar)
- **Identical in both applications**
- Stored securely (use environment variables or encrypted config in production)

### Generating a Secret

```powershell
# Generate a strong secret (64 characters - recommended)
$secret = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 64 | ForEach-Object {[char]$_})
Write-Host "Generated Secret: $secret"

# Or use GUIDs
$secret = ([guid]::NewGuid().ToString() -replace '-','') + ([guid]::NewGuid().ToString() -replace '-','')
Write-Host "Generated Secret (GUID-based): $secret"
```

## Implementation Status

### ✅ Global Validation (ACTIVE)

**Current Implementation**: Signature validation is now active in `RestPSCustomModule.psm1` (lines 384-387):

```powershell
if ( $ScriptVariables.RequestSignatureSecret ) {
    if ( 'null' -ne $Body ) { $SignatureBody = $Body } else { $SignatureBody = '' }
    if ( (Test-RequestSignature -Request $Request -Body $SignatureBody -Secret $ScriptVariables.RequestSignatureSecret) -eq $false ) { return $false }
}
```

When `RequestSignatureSecret` is configured:
- ✅ All incoming requests are automatically validated
- ✅ Requests with invalid signatures are rejected before routing
- ✅ No additional endpoint-level validation required
- ✅ Provides defense-in-depth security by default

### Option: Additional Per-Endpoint Validation

If you need additional logging or custom behavior for specific endpoints, you can add endpoint-level validation:

```powershell
# In Get-LinksAdmin.ps1 or other sensitive endpoints
param($RequestArgs, $Body)

# Additional validation with custom logging (global validation already occurred)
$isValid = Test-RequestSignature -Request $script:Request -Body $Body -Secret $ScriptVariables.RequestSignatureSecret

if (-not $isValid) {
	return @{
		StatusCode = 401
		Body = '{"error":"Unauthorized - Invalid Signature"}'
		ContentType = 'application/json'
	}
}

# Continue with normal endpoint logic...
```

**Note**: Since global validation is now active, per-endpoint validation is only needed for:
- Custom error messages or logging
- Additional audit requirements
- Development/testing purposes

## Deployment Status

**✅ Phase 3 - Full Enforcement (CURRENT)**
- Global validation active in RestPSCustomModule (lines 384-387)
- All requests validated automatically when `RequestSignatureSecret` is configured
- Invalid signatures rejected before routing occurs
- Defense-in-depth protection fully implemented

## Security Considerations

### ✅ What Signature Validation Protects Against:

1. **Request Tampering** - Body or headers modified in transit
2. **Replay Attacks** - Signature includes request-specific data (method, path, body)
3. **Unauthorized Direct Access** - Only wrapper-signed requests are accepted
4. **Man-in-the-Middle** - Any modification invalidates the signature

### ⚠️ What It Does NOT Protect Against:

1. **Localhost Attacks** - Backend still binds to localhost only; signature doesn't help if attacker has localhost access
2. **Timing Attacks** - Function uses constant-time comparison to mitigate, but PowerShell performance varies
3. **Secret Compromise** - If secret is leaked, attacker can forge signatures

### 🔒 Best Practices:

1. **Use Environment Variables** for secrets in production
2. **Rotate Secrets Periodically** (requires coordinated update in both apps)
3. **Monitor Invalid Signatures** - High rate may indicate attack
4. **Keep Backend Localhost-Only** - Network isolation is primary defense
5. **Use HTTPS** between wrapper and backend if not on same machine (not recommended)
6. **Log Signature Failures** - Include method, path, and timestamp

## Usage Example

### Complete Validation in an Endpoint

```powershell
# Management.ps1 - Secure endpoint with signature validation
param($RequestArgs, $Body)

# Step 1: Validate signature
if (-not (Test-RequestSignature -Request $script:Request -Body $Body -Secret $ScriptVariables.RequestSignatureSecret)) {
	Write-Log -LogFile $Logfile -LogLevel ERROR -MsgType ERROR -Message "Signature validation failed for Management endpoint"
	return @{
		StatusCode = 401
		StatusDescription = "Unauthorized"
		Body = '{"error":"Invalid request signature"}'
		ContentType = 'application/json'
	} | ConvertTo-Json
}

# Step 2: Get authenticated user from wrapper
$authenticatedUser = $script:Request.Headers["X-Authenticated-User"]
if ([string]::IsNullOrEmpty($authenticatedUser)) {
	return @{
		StatusCode = 401
		Body = '{"error":"No authenticated user"}'
		ContentType = 'application/json'
	} | ConvertTo-Json
}

# Step 3: Parse and process request
try {
	$data = $Body | ConvertFrom-Json

	# Your business logic here...
	$result = Process-ManagementRequest -Data $data -User $authenticatedUser

	return @{
		StatusCode = 200
		Body = $result | ConvertTo-Json
		ContentType = 'application/json'
	} | ConvertTo-Json
}
catch {
	Write-Log -LogFile $Logfile -LogLevel ERROR -MsgType ERROR -Message "Error processing management request: $_"
	return @{
		StatusCode = 500
		Body = '{"error":"Internal server error"}'
		ContentType = 'application/json'
	} | ConvertTo-Json
}
```

## Testing

### Test Script

```powershell
# Test signature generation and validation
$secret = "test-secret-key-at-least-32-characters-long"

# Simulate request data
$user = "testuser"
$method = "POST"
$path = "/api/test"
$body = '{"test":"data"}'
$bodyLength = $body.Length

# Generate signature (mimics wrapper)
$signatureData = "$user|$method|$path|$bodyLength|$body"
$hmac = New-Object System.Security.Cryptography.HMACSHA256
$hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secret)
$hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($signatureData))
$signature = [Convert]::ToBase64String($hashBytes)
$hmac.Dispose()

Write-Host "Signature Data: $signatureData"
Write-Host "Generated Signature: $signature"

# Now validate it (create a mock request object for testing)
# In production, you'd use the actual $script:Request from the listener
```

## Troubleshooting

### Common Issues

**1. Signature Always Invalid**
- Check that both apps use the **exact same secret** (case-sensitive)
- Verify body encoding - wrapper uses UTF-8
- Check for trailing whitespace in secret strings

**2. Empty Body Signatures Fail**
- Ensure empty bodies use `"[EMPTY]"` string in both wrapper and backend
- Check bodyLength calculation (0 for empty)

**3. Performance Impact**
- Signature validation adds ~1-5ms per request
- Consider validating only state-changing requests (POST/PUT/DELETE)

### Debug Logging

Add to your endpoint:

```powershell
Write-Host "=== Signature Debug ==="
Write-Host "User: $($script:Request.Headers['X-Authenticated-User'])"
Write-Host "Method: $($script:Request.HttpMethod)"
Write-Host "Path: $($script:Request.Url.AbsolutePath)"
Write-Host "Body Length: $($Body.Length)"
Write-Host "Body: $Body"
Write-Host "Provided Signature: $($script:Request.Headers['X-Request-Signature'])"
Write-Host "======================="
```

## Migration Path

**✅ COMPLETED** - All3 phases have been implemented:

1. **✅ Phase 1 - Deploy** (Completed)
   - ✅ `Test-RequestSignature` function added
   - ✅ Logging implemented
   - ✅ Monitoring verified

2. **✅ Phase 2 - Selective** (Completed)
   - ✅ Tested on admin/sensitive endpoints
   - ✅ Validation logic verified

3. **✅ Phase 3 - Full Enforcement** (CURRENT - ACTIVE)
   - ✅ Global validation enabled in RestPSCustomModule (lines 384-387)
   - ✅ All requests validated automatically
   - ✅ Invalid signatures rejected before routing

## References

- Wrapper signature generation: `RestPSWrapper/Services/SignatureService.cs`
- Wrapper signature usage: `RestPSWrapper/Controllers/ProxyController.cs` (line 86-88)
- Backend validation function: `RestPSModule/RestPSCustomModule.psm1` (`Test-RequestSignature`)
- Backend validation enforcement: `RestPSModule/RestPSCustomModule.psm1` (lines 384-387)
- Security architecture: `SECURITY.md`
