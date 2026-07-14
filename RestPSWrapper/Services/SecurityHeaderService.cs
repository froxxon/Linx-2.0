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

    public void ApplySecurityHeaders(HttpResponse response, string? nonce = null)
    {
        try
        {
            // Cache Control - prevent caching of dynamic content
            response.Headers["Cache-Control"] = _config.HTMLCacheControl;
            response.Headers["Pragma"] = "no-cache";
            response.Headers["Expires"] = "0";

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
                _logger.LogDebug("CSP header set: {CSP}", csp);
            }
            else
            {
                _logger.LogDebug("CSP not set (empty configuration)");
            }

            // Prevent MIME type sniffing
            response.Headers["X-Content-Type-Options"] = _config.HTMLXContentTypeOptions;

            // Set content language to prevent browser translation prompts
            if (!string.IsNullOrEmpty(_config.ContentLanguage))
            {
                response.Headers["Content-Language"] = _config.ContentLanguage;
                _logger.LogDebug("Content-Language header set: {Language}", _config.ContentLanguage);
            }

            // Prevent clickjacking
            response.Headers["X-Frame-Options"] = "DENY";

            // Prevent opening in XFRAME
            response.Headers["X-Frame-Options"] = "SAMEORIGIN";

            // Disable cross-domain policies
            response.Headers["X-Permitted-Cross-Domain-Policies"] = "none";

            // Remove server identification
            response.Headers.Remove("Server");
            response.Headers.Remove("X-AspNet-Version");
            response.Headers.Remove("X-PoweredBy");

            // HSTS - Force HTTPS (only on HTTPS responses)
            if (response.HttpContext.Request.IsHttps)
            {
                var hstsMaxAge = _config.HstsMaxAgeDays * 86400; // Convert days to seconds
                response.Headers["Strict-Transport-Security"] = $"max-age={hstsMaxAge}; includeSubDomains; preload";
            }

            _logger.LogDebug("Security headers applied successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error applying security headers");
            // Don't throw - security headers failure shouldn't block response
        }
    }
}