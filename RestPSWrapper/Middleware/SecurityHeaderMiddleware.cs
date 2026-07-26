using RestPSWrapper.Services;

namespace RestPSWrapper.Middleware;

/// <summary>
/// Middleware that applies security headers to all responses early in the pipeline
/// This ensures auth-generated 401/403 responses also have security headers
/// </summary>
public class SecurityHeaderMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ISecurityHeaderService _securityHeaderService;

    public SecurityHeaderMiddleware(
        RequestDelegate next,
        ISecurityHeaderService securityHeaderService)
    {
        _next = next;
        _securityHeaderService = securityHeaderService;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Generate CSP nonce for security headers
        var nonce = System.Security.Cryptography.RandomNumberGenerator.GetHexString(16);
        context.Items["CspNonce"] = nonce;

        // Apply security headers early so they're on all responses (including auth failures)
        var protectedHeaders = _securityHeaderService.ApplySecurityHeaders(context.Response, nonce);
        context.Items["ProtectedHeaders"] = protectedHeaders;

        await _next(context);
    }
}
