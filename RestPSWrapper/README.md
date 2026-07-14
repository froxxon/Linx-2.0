# RestPS Wrapper - ASP.NET Core

ASP.NET Core wrapper that bridges IIS (Kerberos authentication, HTTPS) with PowerShell REST endpoints running on localhost.

## Architecture

```
IIS (Port 443, HTTPS, Kerberos Auth)
  ↓
ASP.NET Core (Kestrel, Middleware)
  ↓
PowerShell Endpoints (localhost:8080+, HTTP)
```

## Features

- **Kerberos Authentication** via IIS and Negotiate middleware
- **HTTPS/SSL** support
- **Route Management** - Routes loaded from JSON configuration
- **Request Logging** - All requests logged with user identity
- **Security Headers** - CSP, CORS, cache control, and more
- **Secure User Authentication** - HMAC-SHA256 signed headers
- **CSRF Protection** - Token-based protection for state-changing requests
- **Gzip Compression** - For API responses and assets
- **Reverse Proxy** - Forwards requests to PowerShell endpoints
- **Configuration** - All settings in appsettings.json (mirrors $ScriptVariables)
- **Dynamic HTML Variables** - PSVar_* configuration properties replaced in HTML templates
- **Rate Limiting** - Configurable per-user/IP request throttling

## Project Structure

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
```

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

## Configuration

### appsettings.json

The `ScriptVariables` section contains all configuration that was previously in PowerShell:

```json
"ScriptVariables": {
  "ListenerUrl": "https://localhost:443",
  "ShortURL": "localhost",
  "ScriptPath": "C:/RestPS",
  "RoutesFilePath": "C:/RestPS/endpoints/RestPSRoutes.json",
  "LogDirectory": "C:/RestPS/logs",
  "LogLevel": "INFO",
  "HTMLContentTypeCharset": "utf-8",
  "HTMLCacheControl": "no-cache, no-store, must-revalidate",
  "HTMLContentSecurityPolicy": "default-src 'self'; script-src 'self' 'nonce-{nonce}'; style-src 'self' 'unsafe-inline'",
  "HTMLXContentTypeOptions": "nosniff",
  "AccessControlAllowOrigin": "",
  "AccessControlAllowMethods": "",
  "Domain": "YOURDOMAIN",
  "SQLServer": "localhost",
  "Database": "RestPS",
  "PowerShellPort": 8080,
  "RequestSignatureSecret": "change-this-to-a-secure-random-key",
  "IncludeUserEmail": false,
  "IncludeUserDisplayName": false,
  "IncludeUserGroups": false,
  "IncludeUserSID": false
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

## Services

### IRouteService
Loads and caches routes from JSON configuration file. Reloads on each request to pick up new routes (like the PowerShell module).

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

## Environment-specific Settings

- `appsettings.json` - Default settings
- `appsettings.Development.json` - Development overrides (debug logging)
- `appsettings.Production.json` - Production overrides (URLs, log level)
