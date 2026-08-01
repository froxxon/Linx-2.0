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
- **Purpose**: Allows future backend validation to detect tampering

**Current Status**: Signatures are generated but **not yet validated** by the backend.

**Future Enhancement**: Backend signature validation will be added in a later stage for additional defense-in-depth protection.

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

### Future Enhancements:
🔜 Backend signature validation (defense-in-depth)  
🔜 Backend request origin verification  
🔜 Backend rate limiting (secondary layer)

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
- **Current**: Request signing implemented, validation planned for future release
- **Planned**: Backend signature validation for defense-in-depth
