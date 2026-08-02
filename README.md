![Logo](Linx/images/logo_default.png)

# Linx-2.0

A re-brand of the Linx project using an ASP.NET Core wrapper as a bridge between IIS and PowerShell.  
An *on-prem* web site for web links, based on RestPS.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Security](#security)
  - [Security Architecture](#security-architecture)
  - [Request Signature Validation](#request-signature-validation)
  - [Protected Headers](#protected-headers)
  - [Security Best Practices](#security-best-practices)
- [PowerShell Backend](#powershell-backend)
- [Services & Middleware](#services--middleware)
- [Dynamic HTML Variables](#dynamic-html-variables)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Screenshots](#screenshots)

---

## Overview

*A **strong** recommendation is always to test new things in a lab environment, if such exist, first hand ;) The information provided here is 'as is' until otherwise mentioned!*

Ever felt confused when joining a new firm about where to find things? Some things are known by him, her, that and/or maybe even this...  
No worries, now if you have some Windows server just idling you can quite easily gather all these pieces in one place and share the knowledge with others.  
This place would in this scenario be, you've probably already guessed it, Linx.

---

## Features

### Linx Application Features

- Enable/disable use of personal themes (3 different themes available)
- Enable/disable use of personal links/categories
- Categorize, tag and filter links to find them fast
- Role-based Access Control *per* link
- Role-based Access Control for editors and admins
- OU-based access control for regular users
- Customize (*some*) CSS in web interface Customize regular expressions used to your need
- No database needed - all stored locally (*with pros and cons coming with that approach*)
- Support for multiple languages (currently English and Swedish)
- Fully customizable (*as long as you know your PS*)
- Add notes and a potential contact to each link
- Uses "*System.Net.HttpListener*"
- New logo

### RestPSWrapper Features

- **Kerberos Authentication** via IIS and Negotiate middleware
- **HTTPS/SSL** support
- **Dynamic Route Reloading** - Routes automatically reload when file changes (hash-based detection)
- **Request Signature Validation** - HMAC-SHA256 signature verification in PowerShell backend
- **Request Logging** - All requests logged with user identity
- **Security Headers** - CSP, CORS, cache control, and more
- **Secure User Authentication** - HMAC-SHA256 signed headers
- **CSRF Protection** - Token-based protection for state-changing requests
- **Gzip Compression** - For API responses and assets
- **Reverse Proxy** - Forwards requests to PowerShell endpoints
- **Configuration** - All settings in appsettings.json (mirrors $ScriptVariables)
- **Dynamic HTML Variables** - PSVar_* configuration properties replaced in HTML templates
- **Rate Limiting** - Configurable per-user/IP request throttling

---

## Architecture

```
IIS (Port 443, HTTPS, Kerberos Auth)
  ↓
ASP.NET Core (Kestrel, Middleware)
  ↓
PowerShell Endpoints (localhost:8080+, HTTP)
```

### Two-Layer Defense-in-Depth Model

1. **Public-facing .NET Wrapper (RestPSWrapper)** - Handles authentication, authorization, and security controls
2. **Internal PowerShell Backend (Linx/RestPSModule)** - Processes requests in a protected environment

### Project Structure

```
RestPSWrapper/
├── Configuration/
│   ├── Route.cs                      # Route definition model
│   └── ScriptVariablesConfig.cs      # Configuration binding (mirrors appsettings.json)
├── Controllers/
│   ├── CsrfController.cs             # CSRF token management endpoints
│   └── ProxyController.cs            # Main reverse proxy with HTML templating
├── Middleware/
│   ├── CompressionMiddleware.cs      # Gzip compression
│   ├── GlobalExceptionHandlerMiddleware.cs
│   ├── RateLimitingMiddleware.cs
│   ├── RequestIdMiddleware.cs
│   ├── RequestLoggingMiddleware.cs
│   ├── RequestSizeLimitMiddleware.cs
│   └── SecurityMiddleware.cs         # Unified security (Origin, CSRF, CSP, headers)
├── Services/
│   ├── ICsrfTokenService.cs          # CSRF token generation & validation
│   ├── IPowerShellProxyService.cs    # HTTP forwarding to PowerShell
│   ├── IRouteService.cs              # Route loading & caching
│   ├── ISecurityHeaderService.cs     # Security header management
│   ├── IUserContextService.cs        # User identity & AD queries
│   └── SignatureService.cs           # HMAC request signing
├── Filters/
│   └── AuditLoggingFilter.cs         # Action-level audit logging
├── appsettings.json                  # Main configuration
├── Program.cs                        # Application bootstrap & DI
└── RestPSWrapper.csproj              # .NET 10 project file

Linx/
├── endpoints/                        # PowerShell REST endpoints
│   ├── Get-Links.ps1                # Main listing endpoint
│   ├── Get-LinksAdmin.ps1           # Admin interface
│   ├── Get-LinksPersonal.ps1        # Personal links
│   ├── Management.ps1               # Link CRUD operations
│   └── Routes.json                  # Route configuration
├── modules/
│   └── Internal-CmdLets.psm1        # Linx-specific helper functions
├── Start-Service.ps1                # Backend startup script
└── base_settings.json               # Backend configuration

RestPSModule/
└── RestPSCustomModule.psm1          # Shared RestPS listener module
```

---

## Installation

- Run the script "*bin\Set-Service.ps*" in an elevated Powershell prompt (*assign different parameters if NSSM or Linx paths are changed*)

- Open "*services.msc*" elevated and find the service "*Linx*"
   
   - Right-click and select "*Properties*" \ "*Log on*" \ "*This account*"
   
   - Enter the gMSA service account, clear the password fields and save by pressing "*OK*"

- Open an elevated command prmopt and run these two commands (*this is included in RestPS originally, but don't want the requirement of being a local admin to run it*):
   
   - Replace FQDN, Port and Thumbprint used to match your environment:
   
     ```netsh http add sslcert hostnameport=linx.domain.local:443 appid={2a81d04e-f297-46a6-b17a-3580fa3d91a5} certhash=THUMBPRINT certstorename=My```
   
   - Replace FQDN, Port, Domain and the gMSA service account used to match your environment
   
     ```netsh http add urlacl url="https://linx.domain.local:443/" user="DOMAIN\gMSA-Linx$"```
 
- Configure "*base_settings.json*" to match your environment:
   
   - *ServerURL:* https://linx.domain.local (*post https:// must match CN or SAN in certificate*)
   
   - *ShortURL:* linx.domain.local (*FQDN*)
   
   - *Domain:* DOMAIN (*short name of the domain*)
   
   - *SSLThumbprint:* Check your certificates thumbprint and paste it here
   
   - *AdminGroup:* Common name of the group containing Linx-administrators
   
   - *EditGroup:* Common name of the group containing Linx-editors (*a.k.a. admins without sugar*)
   
   - *OU_Admin:* Distinguished name for the OU which holds your administrative accounts, if those shall have access to Linx
   
   - *OU_Group:* Distinguished name for the OU containing the Admin and Edit Linx groups
   
   - *OU_User:* Distinguished namr for the OU containing the standard users of Linx

    *Port and Language could also be specified if necessary...*

 - Set file and folder permissions for gMSA service account
   - gMSA minimum permissions (*recommended*):
   
      - "*Delete*" files under "*bin\Personal*"
   
      - "*Modify*" on the following subfolders and files:
      
         - bin (*folder*)
      
         - images (*folder*)
      
         - lang (*folder*)
      
         - logs (*folder*)
      
         - settings (*folder*)
      
         - style (*folder*)
      
         - base_settings.json

   - gMSA sloppy ACLs (**not** *recommended*):
   
      - "*Full Control*" on Linx subfolders and files
 
- Start the service and go to Linx from another machine to start using it

## POST-INSTALLATION
- Every now and then your certificate will expire, then:
   
   - Order a new certificate according to your local routines
   
   - Open "*certlm.msc*" and add the certificate to "*Personal*" \ "*Certificates*"
   
   - Remove the old certificate in the same store (*recommended*)
   
   - Open an elevated command prompt and run (*changes values to match your environment*):
   
      ```netsh http delete sslcert hostnameport=linx.domain.local:443```
      
      ```netsh http add sslcert hostnameport=linx.domain.local:443 appid={2a81d04e-f297-46a6-b17a-3580fa3d91a5} certhash=THUMBPRINT certstorename=My```
   - Open "*base_settings.json*' in an elevated editor and change "*SSLThumbprint*" to the one matching the new certificate
   
   - Restart the service

## TROUBLESHOOTING
- The service won't start:
   - Verify that the minimum ACLs are set accordingaly
   
- The service *still* won't start:
   - Run "*Start-Service.ps1*" in a Powershell prompt started as the gMSA service account for further analysis

## INSTRUCTIONS

### MENU

When you start the site for the first time you will have access to this menu if you login as Admin.
The tab "*ADMIN*" will show if you have Edit permissions as well, but will be hidden for regular users.
Selection of themes (*to the right*) is also an available setting to turn off if you desire for all users.


## Configuration

### appsettings.json

The `ScriptVariables` section contains all configuration that was previously in PowerShell:

```json
"ScriptVariables": {
  "ListenerUrl": "https://localhost:443",
  "ScriptPath": "${RESTPS_HOME:C:/RestPS}",
  "RoutesFilePath": "${RESTPS_HOME:C:/RestPS}/endpoints/Routes.json",
  "LogDirectory": "${RESTPS_HOME:C:/RestPS}/logs",
  "LogLevel": "INFO",
  "HTMLCacheControl": "no-cache, no-store, must-revalidate",
  "HTMLContentSecurityPolicy": "block-all-mixed-content; base-uri 'none'; object-src 'none';",
  "HTMLXContentTypeOptions": "nosniff",
  "ContentLanguage": "sv-SE",
  "AccessControlAllowOrigin": "",
  "AccessControlAllowMethods": "",
  "PowerShellServiceUrl": "http://localhost:8080",
  "RequestSignatureSecret": "${RESTPS_SIGNATURE_SECRET}",
  "IncludeUserEmail": false,
  "IncludeUserDisplayName": false,
  "IncludeUserGroups": false,
  "IncludeUserSID": false,
  "EnforceCorsOriginValidation": true,
  "TrustedOrigins": "",
  "RequireCsrfToken": true,
  "CsrfTokenHeaderName": "X-CSRF-Token",
  "CsrfTokenExpirationSeconds": 3600,
  "CsrfBypassPaths": "/api/csrf/token,/api/csrf/health,/health",
  "MaxRequestBodySizeBytes": 10485760,
  "RateLimitRequestsPerMinute": 300,
  "RateLimitBypassForLocalhost": true,
  "HstsMaxAgeDays": 365,
  "PSVar_PageTitle": "Application",
  "PSVar_PageDescription": "",
  "PSVar_HTMLLanguage": "sv"
}
```

## Secure Authentication Headers

When forwarding requests to PowerShell endpoints, the wrapper adds secure headers that cannot be spoofed by clients:

### Always Included (Secure)
- **X-Authenticated-User** - User identity from Kerberos (e.g., `DOMAIN\username`)
- **X-Request-Signature** - HMAC-SHA256 signature of `username|method|path|body`

### Optional Headers (Configurable)
Enable these in `appsettings.json` if needed:

- **X-User-Email** - User's email address (requires AD query)
  - Set `IncludeUserEmail: true`
- **X-User-Display-Name** - User's display name (requires AD query)
  - Set `IncludeUserDisplayName: true`
- **X-User-Groups** - User's AD groups, comma-separated (requires AD query)
  - Set `IncludeUserGroups: true`
- **X-User-SID** - User's Security Identifier
  - Set `IncludeUserSID: true`

### How to Use in PowerShell

```powershell
# In your PowerShell endpoint script
$authenticatedUser = $Request.Headers['X-Authenticated-User']
$signature = $Request.Headers['X-Request-Signature']

Write-Host "Request from user: $authenticatedUser"
Write-Host "Request signature: $signature"

# Optional: Get additional user info if configured
if ($Request.Headers.ContainsKey('X-User-Email')) {
    $email = $Request.Headers['X-User-Email']
    Write-Host "User email: $email"
}
```

### Security Note

The signature is computed using a secret key (`RequestSignatureSecret`) that should be:
1. **Changed from the default** in production
2. **Kept secure** - store in environment variables or secret manager
3. **Same on both sides** - the PowerShell endpoints can validate signatures if needed

## CSRF Protection

The wrapper includes built-in CSRF (Cross-Site Request Forgery) protection for all state-changing requests (POST, PUT, PATCH, DELETE).

### How CSRF Protection Works

1. **Session Cookie**: When a user first accesses the API, a secure `SessionId` cookie is automatically created
2. **Token Generation**: The server generates a unique CSRF token tied to the session
3. **Token Delivery**: The token is sent to the client in the `X-CSRF-Token` response header
4. **Token Validation**: State-changing requests must include the token in the `X-CSRF-Token` request header
5. **Automatic Refresh**: Each response includes a new token for the next request

### Configuration

```json
"ScriptVariables": {
  "RequireCsrfToken": true,
  "CsrfTokenHeaderName": "X-CSRF-Token",
  "CsrfTokenExpirationSeconds": 3600,
  "CsrfBypassPaths": "/api/csrf/token,/api/csrf/health,/health"
}
```

### Getting a CSRF Token

**Endpoint**: `GET /api/csrf/token`

This endpoint is always accessible (bypasses CSRF validation) and returns:

```json
{
  "token": "base64-encoded-token-here",
  "headerName": "X-CSRF-Token",
  "expiresIn": "3600 seconds",
  "usage": "Include this token in the X-CSRF-Token header for POST/PUT/PATCH/DELETE requests"
}
```

### Using CSRF Tokens

#### PowerShell Example

```powershell
# Step 1: Get CSRF token
$response = Invoke-RestMethod `
    -Uri "https://localhost:443/api/csrf/token" `
    -Method GET `
    -UseDefaultCredentials `
    -SessionVariable session

$csrfToken = $response.token

# Step 2: Use token in POST request
$body = @{ data = "value" } | ConvertTo-Json
Invoke-RestMethod `
    -Uri "https://localhost:443/api/your-endpoint" `
    -Method POST `
    -Headers @{ "X-CSRF-Token" = $csrfToken } `
    -Body $body `
    -ContentType "application/json" `
    -UseDefaultCredentials `
    -WebSession $session
```

#### JavaScript Example

```javascript
// Step 1: Get CSRF token
let csrfToken = null;

async function getCsrfToken() {
    const response = await fetch('/api/csrf/token', {
        method: 'GET',
        credentials: 'include'  // Important for cookies
    });
    const data = await response.json();
    csrfToken = data.token;
}

// Step 2: Use token in POST request
async function postData(data) {
    await getCsrfToken();  // Get token if not already available

    const response = await fetch('/api/your-endpoint', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrfToken
        },
        credentials: 'include',
        body: JSON.stringify(data)
    });

    // Update token from response for next request
    csrfToken = response.headers.get('X-CSRF-Token');

    return response.json();
}
```

### Important Notes

- **GET requests**: Do NOT require CSRF tokens
- **POST/PUT/PATCH/DELETE requests**: MUST include a valid CSRF token
- **Cookies**: Must be enabled (SessionId cookie is required)
- **HTTPS**: Required in production (cookies are marked Secure)
- **Token Refresh**: Each response includes a new token in the `X-CSRF-Token` header
- **Token Expiration**: Tokens expire after 1 hour (configurable)

### CSRF Endpoints

- `GET /api/csrf/token` - Get a new CSRF token
- `POST /api/csrf/invalidate` - Invalidate current session tokens (logout)
- `GET /api/csrf/health` - Health check for CSRF service

### Disabling CSRF (Development Only)

For development/testing, you can temporarily disable CSRF protection:

```json
"RequireCsrfToken": false
```

**Warning**: Never disable CSRF in production environments!

## Log Levels

- `TRACE` - Verbose diagnostic logging
- `DEBUG` - Debug information
- `INFO` - General information (default)
- `WARN` - Warning messages
- `ERROR` - Error messages
- `FATAL` - Fatal errors

## Building

```bash
dotnet build RestPSWrapper.csproj
```

## Publishing

### Self-contained executable
```bash
dotnet publish -c Release -r win-x64 --self-contained
```

### IIS deployment
```bash
dotnet publish -c Release -o C:\inetpub\wwwroot\RestPS
```

## IIS Configuration

1. Create an IIS application pointing to the published folder
2. Enable Windows Authentication (Negotiate)
3. Configure HTTPS binding with your certificate
4. Set application pool identity to run as application user
5. Ensure PowerShell endpoints are accessible on localhost:8080
6. Update `appsettings.json` with:
   - Correct `ListenerUrl`
   - Path to `RoutesFilePath`
   - `RequestSignatureSecret` (use a strong random value)

## Running

### Development
```bash
dotnet run --configuration Development
```

### Production
```bash
dotnet run --configuration Production
```


---

## Security

# Security Architecture

## Overview

This project implements a defense-in-depth security architecture with two layers:
1. **Public-facing .NET Wrapper** (RestPSWrapper) - Handles authentication, authorization, and security controls
2. **Internal PowerShell Backend** (Linx/RestPSModule) - Processes requests in a protected environment

## Security Boundaries

### Layer 1: .NET Wrapper (RestPSWrapper)
The public-facing layer provides:
- **Authentication**: Kerberos/Negotiate (Windows Integrated Authentication)
- **Authorization**: Role-based access control
- **CSRF Protection**: Token-based validation for state-changing requests
- **Rate Limiting**: Per-IP request throttling
- **Security Headers**: CSP, X-Frame-Options, HSTS, etc.
- **Input Validation**: Request size limits, content type validation
- **Request Signing**: HMAC-SHA256 signatures sent to backend

**Endpoint**: Configured via `ListenerUrl` (default: `http://+:8088`)

### Layer 2: PowerShell Backend (Linx/RestPSModule)
The internal processing layer:
- **Network Isolation**: Binds to `localhost` only (not exposed externally)
- **Anonymous Authentication**: By design - network isolation is the security boundary
- **Request Processing**: Executes PowerShell scripts based on route configuration

**Endpoint**: `http://localhost:8080` (localhost-only by design)

## Current Security Model

### Why Anonymous Authentication in Backend?

The PowerShell backend uses `Anonymous` authentication intentionally because:

1. **Network Isolation**: Backend binds to `localhost:8080` only - not accessible from external networks
2. **Single Point of Entry**: All external requests MUST go through the .NET wrapper
3. **Simplified Architecture**: Authentication/authorization logic in one place (wrapper)
4. **Defense in Depth**: Wrapper provides multiple security layers before reaching backend

### Request Signing (Defense-in-Depth)

The wrapper generates HMAC-SHA256 signatures for all forwarded requests:
- **Header**: `X-Request-Signature`
- **Signature Data**: `{user}|{method}|{path}|{bodyLength}|{body}`
- **Purpose**: Backend validates signatures to detect tampering and ensure requests originated from the authorized wrapper

**Current Status**: ✅ **IMPLEMENTED** - Signatures are generated by the wrapper and validated by the backend.

**Implementation**: Backend validation occurs in `RestPSCustomModule.psm1` (lines 384-387), automatically rejecting requests with invalid or missing signatures when `RequestSignatureSecret` is configured.

## Configuration Security

### Localhost-Only Binding (Critical)
Ensure `base_settings.json` contains:
```json
{
  "ShortURL": "localhost"
}
```
**WARNING**: Never change this to `"0.0.0.0"` or `"+"` as it would expose the unauthenticated backend externally.

### Wrapper Backend URL
The wrapper must connect to localhost backend:
```json
{
  "PowerShellServiceUrl": "http://localhost:8080"
}
```

### AllowedHosts Configuration

The `AllowedHosts` setting in `appsettings.json` controls Host header validation to prevent Host header injection attacks and cache poisoning.

**Development (Current Default)**:
```json
{
  "AllowedHosts": "*"
}
```
⚠️ **Wildcard `*` disables validation** - acceptable for development but should be restricted in production.

**Production (Recommended)**:
```json
{
  "AllowedHosts": "linx.example.com;www.linx.example.com"
}
```

**Format Rules**:
- **Semicolon-separated** list (`;` not `,`)
- **Hostname only** (no `https://` protocol)
- **Include port** if non-standard: `example.com:8443`
- **Subdomain wildcards** supported: `*.example.com`
- **Multiple domains** allowed: `site1.com;site2.net`

**Examples**:

```json
// Single production domain
"AllowedHosts": "linx.company.com"

// Multiple domains
"AllowedHosts": "linx.company.com;www.linx.company.com;api.linx.company.com"

// Subdomain wildcard
"AllowedHosts": "*.company.com"

// Multiple domains with ports
"AllowedHosts": "linx.company.com:443;backup.company.com:8443"

// Development/localhost
"AllowedHosts": "localhost;127.0.0.1;*"
```

**Security Impact**:
- ✅ **Configured**: Prevents Host header injection, cache poisoning, and routing attacks
- ⚠️ **Wildcard (`*`)**: Disables protection - only use in isolated development environments

**Recommendation**: Set to actual production domain(s) before deployment. Update during deployment automation or use environment variables.

## Threat Model

### Protected Against:
✅ External unauthorized access (Kerberos authentication)  
✅ CSRF attacks (token validation)  
✅ Brute force (rate limiting)  
✅ Clickjacking (X-Frame-Options)  
✅ XSS (Content-Security-Policy)  
✅ Large payload attacks (request size limits)  
✅ Replay attacks (signature includes timestamp/nonce via CSRF)  
✅ Request tampering (HMAC-SHA256 signature validation)

### Future Enhancements:
🔜 Backend rate limiting (secondary layer)  
🔜 Enhanced audit logging with correlation IDs

## Deployment Best Practices

1. **Firewall Rules**: Only expose wrapper port (8088), block backend port (8080)
2. **Process Isolation**: Run backend under least-privilege service account
3. **Monitoring**: Log all authentication failures and rate limit violations
4. **Certificate Management**: Use valid SSL certificates for production (HSTS enabled)
5. **Configuration Review**: Verify `ShortURL` is always `"localhost"`

## Security Contacts

For security issues or questions about this architecture:
- Review code comments in `RestPSCustomModule.psm1` (lines 212-227)
- Review code comments in `ProxyController.cs` (lines 75-90)
- Consult configuration files: `appsettings.json`, `base_settings.json`

## Changelog

- **2024**: Initial security architecture with wrapper layer
- **Current**: Request signing and validation fully implemented
  - Dynamic route reloading with hash-based change detection
  - HMAC-SHA256 signature validation in PowerShell backend


---

### Request Signature Validation

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


---

### Protected Headers

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


---

## PowerShell Backend Features

The PowerShell backend (`RestPSModule/RestPSCustomModule.psm1`) provides additional security and performance features:

### Dynamic Route Reloading

Routes are loaded into memory and automatically reloaded when the Routes.json file changes:

- **Initial Load**: Routes loaded on first request (lines 109-122)
- **Hash-Based Detection**: File hash checked on each request (line 123)
- **Automatic Reload**: Routes reloaded when hash changes (lines 124-136)
- **Error Handling**: Reload failures logged; previous routes remain active
- **Performance**: Hash comparison is fast; full reload only on actual changes

**Benefits**:
- Zero downtime route updates
- No service restart required
- Automatic rollback on reload failure
- Transparent to clients

### Request Signature Validation

All requests from the wrapper are validated using HMAC-SHA256 signatures:

- **Implementation**: Lines 384-387 in `RestPSCustomModule.psm1`
- **Enforcement**: Enabled when `RequestSignatureSecret` is configured
- **Behavior**: Invalid or missing signatures rejected before routing
- **Defense-in-Depth**: Prevents tampering and unauthorized direct access

See `Linx/SIGNATURE-VALIDATION.md` for detailed documentation.

## Services

### IRouteService
Loads and caches routes from JSON configuration file. Routes are automatically reloaded when the file changes in the PowerShell backend (hash-based detection).

### IPowerShellProxyService
Forwards HTTP requests to PowerShell endpoints running on localhost, including secure user authentication headers.

### ISecurityHeaderService
Applies security headers to responses (CSP, CORS, cache control, etc.).

### IUserContextService
Extracts authenticated user information from HttpContext and optionally queries Active Directory for additional user details.

### ISignatureService
Generates and verifies HMAC-SHA256 signatures for secure request authentication.

### ICsrfTokenService
Manages CSRF token generation, validation, session tracking, and expiration with in-memory storage and automatic cleanup.

## Middleware

### RequestLoggingMiddleware
Logs all incoming requests with user identity and response status.

### SecurityMiddleware
Unified security middleware that handles:
- Origin validation against trusted domains
- CSP nonce generation for inline scripts
- Session cookie management
- CSRF token validation for state-changing requests
- CSRF token generation for response headers
- Security header application (CSP, CORS, cache control, etc.)

### CompressionMiddleware
Applies gzip compression to API responses and assets.

### RateLimitingMiddleware
Configurable rate limiting per user/IP to prevent abuse.

### RequestIdMiddleware
Generates unique request IDs for tracing and correlation.

### GlobalExceptionHandlerMiddleware
Centralized exception handling and error response formatting.

### RequestSizeLimitMiddleware
Enforces maximum request body size limits.


## Dynamic HTML Template Variables

RestPSWrapper automatically replaces template variables in HTML responses. Any configuration property starting with `PSVar_` becomes a dynamic variable that can be used in HTML.

### Quick Example

**Configuration (appsettings.json):**
```json
{
  "ScriptVariables": {
    "PSVar_PageTitle": "My App",
    "PSVar_PageLanguage": "en",
    "PSVar_CompanyName": "Acme Corporation",
    "PSVar_SupportEmail": "support@acme.com",
    "PSVar_Version": "1.0.0"
  }
}
```

**HTML:**
```html
<html lang="{{PSVar_PageLanguage}}">
<head>
    <title>{{PSVar_PageTitle}}</title>
</head>
<body>
    <h1>Welcome to {{PSVar_CompanyName}}</h1>
    <p>Version: {{PSVar_Version}}</p>
    <footer>Contact: {{PSVar_SupportEmail}}</footer>
</body>
</html>
```

### Built-in Variables

- `{{nonce}}` - CSP nonce (generated per request for inline scripts/styles)

### Dynamic PSVar Variables

1. Add `PSVar_*` properties to `appsettings.json`
2. Use `{{PSVar_PropertyName}}` in HTML/PowerShell templates
3. Restart application to load changes

**Note:** Placeholder replacement is **case-insensitive**:
- Config: `PSVar_CompanyName` → Template: `{{PSVar_CompanyName}}`, `{{psvar_companyname}}`, or `{{PSVAR_COMPANYNAME}}` all work
- Config: `psVar_Test` → Template: `{{PSVar_Test}}`, `{{psvar_test}}`, or any case variant works
- The prefix check in config is also case-insensitive (`psvar_`, `PSVAR_`, `PSVar_` all accepted)

**Use Cases:**
- Page metadata (title, description, language)
- Branding (company name, logo URLs)
- Contact information
- API endpoints and URLs
- Version numbers and build info
- Environment-specific settings
- Feature flags


---

## Development

### Environment-specific Settings

- `appsettings.json` - Default settings
- `appsettings.Development.json` - Development overrides (debug logging)
- `appsettings.Production.json` - Production overrides (URLs, log level)

### Security Reviews

Detailed security reviews are available in the `Security-review/` folder:
- `Linx-2.0-security-review.md` - Application-layer security review
- `RestPSWrapper-security-review.md` - Transport-layer security review

---

**Project Repository**: https://github.com/froxxon/Linx-2.0

