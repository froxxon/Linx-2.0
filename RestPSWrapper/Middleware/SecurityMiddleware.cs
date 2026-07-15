using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;
using RestPSWrapper.Services;

namespace RestPSWrapper.Middleware;

/// <summary>
/// Security middleware handling CSRF tokens, Origin validation, and security headers
/// </summary>
public class SecurityMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<SecurityMiddleware> _logger;
    private readonly ICsrfTokenService _csrfTokenService;
    private readonly ISecurityHeaderService _securityHeaderService;
    private readonly ScriptVariablesConfig _config;
    private readonly HashSet<string> _trustedOrigins;
    private readonly HashSet<string> _csrfBypassPaths;

    public SecurityMiddleware(
        RequestDelegate next,
        ILogger<SecurityMiddleware> logger,
        ICsrfTokenService csrfTokenService,
        ISecurityHeaderService securityHeaderService,
        IOptions<ScriptVariablesConfig> options)
    {
        _next = next;
        _logger = logger;
        _csrfTokenService = csrfTokenService;
        _securityHeaderService = securityHeaderService;
        _config = options.Value;
        _trustedOrigins = ParseTrustedOrigins();
        _csrfBypassPaths = ParseCsrfBypassPaths();
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // 1. Validate Origin header if CORS validation is enabled
        if (_config.EnforceCorsOriginValidation && !ValidateOrigin(context))
        {
            _logger.LogWarning(
                "Request rejected due to invalid origin. Origin: {Origin}, Method: {Method}, Path: {Path}",
                context.Request.Headers["Origin"], context.Request.Method, context.Request.Path);

            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            await context.Response.WriteAsync("Origin not allowed");
            return;
        }

        // 2. Generate CSP nonce for security headers
        var nonce = GenerateSecureNonce();
        context.Items["CspNonce"] = nonce;

        // 3. Apply security headers (CSP, X-Frame-Options, etc.) and store protected header names
        var protectedHeaders = _securityHeaderService.ApplySecurityHeaders(context.Response, nonce);
        context.Items["ProtectedHeaders"] = protectedHeaders;

        // 4. Get or create session ID
        var sessionId = GetOrCreateSessionId(context);
        context.Items["SessionId"] = sessionId;

        // 5. Validate CSRF token for state-changing requests (BEFORE generating new token)
        if (_config.RequireCsrfToken && IsStateChangingRequest(context.Request.Method) && !IsCsrfBypassPath(context.Request.Path))
        {
            if (!ValidateCsrfToken(context, sessionId))
            {
                _logger.LogWarning(
                    "Request rejected due to invalid CSRF token. User: {User}, Method: {Method}, Path: {Path}, SessionId: {SessionId}",
                    context.User.FindFirst(ClaimTypes.Name)?.Value ?? "Unknown",
                    context.Request.Method, context.Request.Path, sessionId);

                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsync("CSRF token validation failed");
                return;
            }
        }

        // 6. Generate new CSRF token for next request (always done, regardless of request type)
        var newToken = _csrfTokenService.GenerateToken(sessionId);
        context.Response.Headers[_config.CsrfTokenHeaderName] = newToken;

        await _next(context);
    }

    /// <summary>
    /// Validate the Origin header against trusted origins
    /// </summary>
    private bool ValidateOrigin(HttpContext context)
    {
        // If no origin header is present (same-origin request), allow it
        if (!context.Request.Headers.TryGetValue("Origin", out var originHeader))
        {
            return true;
        }

        var origin = originHeader.ToString();

        // Check if origin is in trusted list
        if (_trustedOrigins.Contains(origin))
        {
            _logger.LogDebug("Origin validated: {Origin}", origin);
            return true;
        }

        _logger.LogWarning("Origin not in trusted list: {Origin}", origin);
        return false;
    }

    /// <summary>
    /// Validate CSRF token from request header
    /// </summary>
    private bool ValidateCsrfToken(HttpContext context, string sessionId)
    {
        _logger.LogDebug("CSRF validation starting for session {SessionId}", sessionId);

        if (!context.Request.Headers.TryGetValue(_config.CsrfTokenHeaderName, out var tokenHeader))
        {
            _logger.LogWarning("CSRF token not found in request headers. Expected header: {HeaderName}", _config.CsrfTokenHeaderName);
            return false;
        }

        var token = tokenHeader.ToString();
        _logger.LogDebug("CSRF token found in header (length: {Length})", token.Length);

        var isValid = _csrfTokenService.ValidateToken(sessionId, token);

        if (isValid)
        {
            _logger.LogDebug("CSRF token validation successful for session {SessionId}", sessionId);
        }

        return isValid;
    }

    /// <summary>
    /// Get or create a session ID for the user.
    /// Validates format and binds to authenticated user to prevent session fixation attacks.
    /// </summary>
    private string GetOrCreateSessionId(HttpContext context)
    {
        var username = context.User.FindFirst(ClaimTypes.Name)?.Value ?? "anonymous";

        // Try to get existing session from cookie
        if (context.Request.Cookies.TryGetValue("SessionId", out var sessionId))
        {
            // Validate session ID format (must be a valid GUID)
            if (Guid.TryParse(sessionId, out var sessionGuid))
            {
                // Additional validation: session must be bound to current user
                var expectedSessionPrefix = GenerateUserSessionPrefix(username);

                // Check if this session belongs to the current user
                if (context.Request.Cookies.TryGetValue("SessionUser", out var sessionUser))
                {
                    if (sessionUser == expectedSessionPrefix)
                    {
                        _logger.LogDebug("Valid session found for user {User}: {SessionId}", username, sessionId);
                        return sessionId;
                    }
                    else
                    {
                        _logger.LogWarning(
                            "Session fixation attempt detected - session user mismatch. User: {User}, SessionUser: {SessionUser}",
                            username, sessionUser);
                    }
                }
                else
                {
                    _logger.LogWarning(
                        "Session validation failed - no user binding found for session {SessionId}",
                        sessionId);
                }
            }
            else
            {
                _logger.LogWarning(
                    "Invalid session ID format rejected (not a valid GUID): {SessionId}",
                    sessionId.Length > 50 ? sessionId.Substring(0, 50) + "..." : sessionId);
            }

            // Invalid or mismatched session - invalidate it
            if (!string.IsNullOrEmpty(sessionId))
            {
                _csrfTokenService.InvalidateSession(sessionId);
            }
        }

        // Generate new session ID
        var newSessionId = Guid.NewGuid().ToString();
        var userSessionPrefix = GenerateUserSessionPrefix(username);

        // Store session ID in cookie (HTTP-only, secure)
        context.Response.Cookies.Append(
            "SessionId",
            newSessionId,
            new Microsoft.AspNetCore.Http.CookieOptions
            {
                HttpOnly = true,
                Secure = true,
                SameSite = Microsoft.AspNetCore.Http.SameSiteMode.Strict,
                Expires = DateTimeOffset.UtcNow.AddHours(1)
            });

        // Store user binding in separate cookie
        context.Response.Cookies.Append(
            "SessionUser",
            userSessionPrefix,
            new Microsoft.AspNetCore.Http.CookieOptions
            {
                HttpOnly = true,
                Secure = true,
                SameSite = Microsoft.AspNetCore.Http.SameSiteMode.Strict,
                Expires = DateTimeOffset.UtcNow.AddHours(1)
            });

        _logger.LogInformation("New session created for user {User}: {SessionId}", username, newSessionId);
        return newSessionId;
    }

    /// <summary>
    /// Generate a hash prefix for the user to bind sessions without storing the username in plain text
    /// </summary>
    private static string GenerateUserSessionPrefix(string username)
    {
        using var sha256 = SHA256.Create();
        var hashBytes = sha256.ComputeHash(System.Text.Encoding.UTF8.GetBytes(username));
        // Use first 16 bytes (128 bits) for compact storage
        return Convert.ToBase64String(hashBytes, 0, 16);
    }

    /// <summary>
    /// Check if request is state-changing (requires CSRF protection)
    /// </summary>
    private static bool IsStateChangingRequest(string method)
    {
        return method switch
        {
            "POST" or "PUT" or "PATCH" or "DELETE" => true,
            _ => false
        };
    }

    /// <summary>
    /// Parse trusted origins from configuration string
    /// </summary>
    private HashSet<string> ParseTrustedOrigins()
    {
        var origins = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (string.IsNullOrEmpty(_config.TrustedOrigins))
        {
            _logger.LogWarning("No trusted origins configured. Cross-origin requests will be rejected.");
            return origins;
        }

        var originList = _config.TrustedOrigins
            .Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(o => o.Trim())
            .Where(o => !string.IsNullOrEmpty(o));

        foreach (var origin in originList)
        {
            origins.Add(origin);
        }

        _logger.LogInformation("Trusted origins loaded: {TrustedOriginCount}", origins.Count);
        return origins;
    }

    /// <summary>
    /// Parse CSRF bypass paths from configuration string
    /// </summary>
    private HashSet<string> ParseCsrfBypassPaths()
    {
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (string.IsNullOrEmpty(_config.CsrfBypassPaths))
        {
            _logger.LogInformation("No CSRF bypass paths configured.");
            return paths;
        }

        var pathList = _config.CsrfBypassPaths
            .Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(p => p.Trim())
            .Where(p => !string.IsNullOrEmpty(p));

        foreach (var path in pathList)
        {
            paths.Add(path);
        }

        _logger.LogInformation("CSRF bypass paths loaded: {BypassPathCount} - {Paths}", 
            paths.Count, string.Join(", ", paths));
        return paths;
    }

    /// <summary>
    /// Check if the request path should bypass CSRF validation
    /// </summary>
    private bool IsCsrfBypassPath(PathString requestPath)
    {
        var path = requestPath.Value ?? string.Empty;
        return _csrfBypassPaths.Contains(path);
    }

    /// <summary>
    /// Generate cryptographically secure nonce for CSP
    /// </summary>
    private static string GenerateSecureNonce()
    {
        var nonceBytes = new byte[16];
        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(nonceBytes);
        }
        return Convert.ToBase64String(nonceBytes);
    }
}
