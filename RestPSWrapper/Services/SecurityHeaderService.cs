using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;

namespace RestPSWrapper.Services;

public class SecurityHeaderService : ISecurityHeaderService
{
    private readonly ILogger<SecurityHeaderService> _logger;
    private readonly ScriptVariablesConfig _config;

    public SecurityHeaderService(ILogger<SecurityHeaderService> logger, IOptions<ScriptVariablesConfig> options)
    {
        _logger = logger;
        _config = options.Value;
    }

    public HashSet<string> ApplySecurityHeaders(HttpResponse response, string? nonce = null)
    {
        var protectedHeaders = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            // Cache Control - prevent caching of dynamic content
            response.Headers["Cache-Control"] = _config.HTMLCacheControl;
            protectedHeaders.Add("Cache-Control");

            response.Headers["Pragma"] = "no-cache";
            protectedHeaders.Add("Pragma");

            response.Headers["Expires"] = "0";
            protectedHeaders.Add("Expires");

            // Content Security Policy - prevent XSS
            var csp = _config.HTMLContentSecurityPolicy;

            // Log the original CSP configuration for debugging
            _logger.LogDebug("Original CSP from config: {CSP}", csp);

            if (!string.IsNullOrEmpty(nonce) && !string.IsNullOrEmpty(csp))
            {
                csp = csp.Replace("{nonce}", nonce);
                _logger.LogDebug("CSP after nonce replacement: {CSP}", csp);
            }

            // Only set CSP header if configured (allow empty to disable CSP)
            if (!string.IsNullOrEmpty(csp))
            {
                response.Headers["Content-Security-Policy"] = csp;
                protectedHeaders.Add("Content-Security-Policy");
                _logger.LogDebug("CSP header set: {CSP}", csp);
            }
            else
            {
                _logger.LogDebug("CSP not set (empty configuration)");
            }

            // Prevent MIME type sniffing
            response.Headers["X-Content-Type-Options"] = _config.HTMLXContentTypeOptions;
            protectedHeaders.Add("X-Content-Type-Options");

            // Set content language to prevent browser translation prompts
            if (!string.IsNullOrEmpty(_config.ContentLanguage))
            {
                response.Headers["Content-Language"] = _config.ContentLanguage;
                protectedHeaders.Add("Content-Language");
                _logger.LogDebug("Content-Language header set: {Language}", _config.ContentLanguage);
            }

            // Prevent clickjacking - deny all framing
            response.Headers["X-Frame-Options"] = "DENY";
            protectedHeaders.Add("X-Frame-Options");

            // Disable cross-domain policies
            response.Headers["X-Permitted-Cross-Domain-Policies"] = "none";
            protectedHeaders.Add("X-Permitted-Cross-Domain-Policies");

            // Remove server identification
            response.Headers.Remove("Server");
            response.Headers.Remove("X-AspNet-Version");
            response.Headers.Remove("X-PoweredBy");

            // HSTS - Force HTTPS (only on HTTPS responses)
            if (response.HttpContext.Request.IsHttps)
            {
                var hstsMaxAge = _config.HstsMaxAgeDays * 86400; // Convert days to seconds
                response.Headers["Strict-Transport-Security"] = $"max-age={hstsMaxAge}; includeSubDomains; preload";
                protectedHeaders.Add("Strict-Transport-Security");
            }

            // Protect CORS headers if CORS validation is enabled
            // This prevents PowerShell backend from bypassing CORS restrictions
            if (_config.EnforceCorsOriginValidation)
            {
                protectedHeaders.Add("Access-Control-Allow-Origin");
                protectedHeaders.Add("Access-Control-Allow-Methods");
                protectedHeaders.Add("Access-Control-Allow-Headers");
                protectedHeaders.Add("Access-Control-Allow-Credentials");
                protectedHeaders.Add("Access-Control-Expose-Headers");
                protectedHeaders.Add("Access-Control-Max-Age");
                _logger.LogDebug("CORS headers protected - PowerShell backend cannot override CORS settings");
            }

            _logger.LogDebug("Security headers applied successfully. Protected headers: {Count}", protectedHeaders.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error applying security headers");
            // Don't throw - security headers failure shouldn't block response
        }

        return protectedHeaders;
    }
}