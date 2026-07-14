namespace RestPSWrapper.Configuration;

/// <summary>
/// Configuration class mirroring PowerShell $ScriptVariables
/// Loaded from appsettings.json with environment variable support
/// </summary>
public class ScriptVariablesConfig
{
    /// <summary>HTTP/HTTPS prefix and domain where wrapper listens (documentation/logging)</summary>
    public string ListenerUrl { get; set; } = string.Empty;

    /// <summary>Script base path (supports environment variables like ${RESTPS_HOME})</summary>
    public string ScriptPath { get; set; } = string.Empty;

    /// <summary>Routes JSON file path (supports environment variables)</summary>
    public string RoutesFilePath { get; set; } = string.Empty;

    /// <summary>Directory for log files (supports environment variables)</summary>
    public string LogDirectory { get; set; } = string.Empty;

    /// <summary>Log level: TRACE, DEBUG, INFO, WARN, ERROR, FATAL</summary>
    public string LogLevel { get; set; } = "INFO";

    /// <summary>HTTP response cache control header</summary>
    public string HTMLCacheControl { get; set; } = "no-cache, no-store, must-revalidate";

    /// <summary>Content Security Policy header</summary>
    public string HTMLContentSecurityPolicy { get; set; } = "default-src 'self'; script-src 'self' 'nonce-{nonce}'; style-src 'self' 'unsafe-inline'";

    /// <summary>X-Content-Type-Options header</summary>
    public string HTMLXContentTypeOptions { get; set; } = "nosniff";

    /// <summary>Content-Language header (e.g., 'en', 'sv', 'en-US') - prevents browser translation prompts</summary>
    public string ContentLanguage { get; set; } = "sv-SE";

    /// <summary>CORS Access-Control-Allow-Origin (comma-separated for multiple origins)</summary>
    public string AccessControlAllowOrigin { get; set; } = string.Empty;

    /// <summary>CORS Access-Control-Allow-Methods (comma-separated)</summary>
    public string AccessControlAllowMethods { get; set; } = string.Empty;

    /// <summary>PowerShell backend service URL (e.g., http://localhost:8080 or http://backend-server:9000)</summary>
    public string PowerShellServiceUrl { get; set; } = "http://localhost:8080";

    /// <summary>Secret key for HMAC-SHA256 request signature (MUST be changed in production)</summary>
    public string RequestSignatureSecret { get; set; } = string.Empty;

    /// <summary>Include user email in X-User-Email header (requires AD query)</summary>
    public bool IncludeUserEmail { get; set; } = false;

    /// <summary>Include user display name in X-User-Display-Name header (requires AD query)</summary>
    public bool IncludeUserDisplayName { get; set; } = false;

    /// <summary>Include user AD groups in X-User-Groups header (requires AD query)</summary>
    public bool IncludeUserGroups { get; set; } = false;

    /// <summary>Include user SID in X-User-SID header</summary>
    public bool IncludeUserSID { get; set; } = false;

    /// <summary>CORS: Enforce origin validation against trusted origins list</summary>
    public bool EnforceCorsOriginValidation { get; set; } = true;

    /// <summary>CORS: Comma-separated list of trusted origins (e.g., "https://app.example.com,https://admin.example.com")</summary>
    public string TrustedOrigins { get; set; } = string.Empty;

    /// <summary>CSRF: Require CSRF tokens for state-changing requests (POST, PUT, PATCH, DELETE)</summary>
    public bool RequireCsrfToken { get; set; } = true;

    /// <summary>CSRF: HTTP header name for CSRF token</summary>
    public string CsrfTokenHeaderName { get; set; } = "X-CSRF-Token";

    /// <summary>CSRF: Token expiration time in seconds</summary>
    public int CsrfTokenExpirationSeconds { get; set; } = 3600;

    /// <summary>CSRF: Comma-separated list of paths that bypass CSRF validation (e.g., "/api/csrf/token,/health")</summary>
    public string CsrfBypassPaths { get; set; } = "/api/csrf/token,/api/csrf/health,/health";

    /// <summary>Maximum request body size in bytes (default 10MB). Set to -1 for unlimited.</summary>
    public long MaxRequestBodySizeBytes { get; set; } = 10 * 1024 * 1024; // 10MB

    /// <summary>Rate limiting: Maximum requests per minute per IP address</summary>
    public int RateLimitRequestsPerMinute { get; set; } = 60;

    /// <summary>Rate limiting: Bypass rate limits for localhost requests (development)</summary>
    public bool RateLimitBypassForLocalhost { get; set; } = true;

    /// <summary>HSTS: Max age in days for Strict-Transport-Security header</summary>
    public int HstsMaxAgeDays { get; set; } = 365;

    /// <summary>
    /// Dynamic PowerShell variables dictionary for HTML template replacement
    /// Any configuration property starting with "PSVar_" will be stored here
    /// and can be used in HTML as {{psVar_PropertyName}}
    /// Example: "PSVar_Setting1" in config → {{psVar_Setting1}} in HTML
    /// </summary>
    public Dictionary<string, string> PSVars { get; set; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
}
