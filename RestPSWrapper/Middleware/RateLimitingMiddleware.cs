using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;
using System.Collections.Concurrent;

namespace RestPSWrapper.Middleware;

/// <summary>
/// Middleware to enforce per-IP rate limiting
/// Prevents brute force attacks and DoS
/// </summary>
public class RateLimitingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RateLimitingMiddleware> _logger;
    private readonly int _requestsPerMinute;
    private readonly bool _bypassLocalhost;
    private readonly ConcurrentDictionary<string, (int count, DateTime window)> _requestCounts = new();
    private readonly Timer _cleanupTimer;

    public RateLimitingMiddleware(
        RequestDelegate next,
        ILogger<RateLimitingMiddleware> logger,
        IOptions<ScriptVariablesConfig> options)
    {
        _next = next;
        _logger = logger;
        _requestsPerMinute = options.Value.RateLimitRequestsPerMinute;
        _bypassLocalhost = options.Value.RateLimitBypassForLocalhost;

        // Cleanup expired entries every 2 minutes
        _cleanupTimer = new Timer(
            callback: _ => CleanupExpiredEntries(),
            state: null,
            dueTime: TimeSpan.FromMinutes(2),
            period: TimeSpan.FromMinutes(2));
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Get real client IP - check X-Forwarded-For first (IIS/proxy scenarios)
        var remoteIp = GetClientIpAddress(context);

        // Bypass rate limiting for localhost if configured
        if (_bypassLocalhost && (remoteIp == "127.0.0.1" || remoteIp == "::1" || remoteIp == "localhost"))
        {
            _logger.LogDebug("Rate limiting bypassed for localhost: {IP}", remoteIp);
            await _next(context);
            return;
        }

        // Check rate limit
        var now = DateTime.UtcNow;
        var key = remoteIp;

        _requestCounts.AddOrUpdate(
            key,
            (1, now),
            (_, existing) =>
            {
                var (count, window) = existing;
                var timeSinceWindow = (now - window).TotalSeconds;

                // Reset if window expired (60 seconds)
                if (timeSinceWindow >= 60)
                {
                    return (1, now);
                }
                else
                {
                    return (count + 1, window);
                }
            });

        var (currentCount, windowStart) = _requestCounts[key];

        if (currentCount > _requestsPerMinute)
        {
            var requestId = context.Items["RequestId"]?.ToString() ?? "Unknown";
            _logger.LogWarning(
                "Rate limit exceeded - IP: {RemoteIP}, Count: {Count}, Limit: {Limit}, Window: {Window}s, RequestId: {RequestId}",
                remoteIp, currentCount, _requestsPerMinute, (now - windowStart).TotalSeconds, requestId);

            context.Response.StatusCode = StatusCodes.Status429TooManyRequests;
            context.Response.ContentType = "application/json";
            context.Response.Headers["Retry-After"] = "60";
            await context.Response.WriteAsJsonAsync(new
            {
                error = "Too Many Requests",
                retryAfter = 60,
                requestId = requestId
            });
            return;
        }

        _logger.LogDebug("Rate limit check passed - IP: {IP}, Count: {Count}/{Limit}", remoteIp, currentCount, _requestsPerMinute);
        await _next(context);
    }

    /// <summary>
    /// Get the real client IP address, checking forwarded headers for proxy/IIS scenarios
    /// </summary>
    private string GetClientIpAddress(HttpContext context)
    {
        // Check X-Forwarded-For header (set by IIS/reverse proxies)
        var forwardedFor = context.Request.Headers["X-Forwarded-For"].FirstOrDefault();
        if (!string.IsNullOrEmpty(forwardedFor))
        {
            // X-Forwarded-For can contain multiple IPs (client, proxy1, proxy2...)
            // Take the first one (original client)
            var ips = forwardedFor.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (ips.Length > 0)
            {
                _logger.LogDebug("Using X-Forwarded-For IP: {IP}", ips[0]);
                return ips[0];
            }
        }

        // Fallback to remote IP address
        var remoteIp = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        _logger.LogDebug("Using RemoteIpAddress: {IP}", remoteIp);
        return remoteIp;
    }

    /// <summary>
    /// Clean up expired rate limit entries to prevent memory leak
    /// </summary>
    private void CleanupExpiredEntries()
    {
        var now = DateTime.UtcNow;
        var expiredKeys = _requestCounts
            .Where(kvp => (now - kvp.Value.window).TotalSeconds > 120) // Keep entries for 2 minutes after window expires
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var key in expiredKeys)
        {
            _requestCounts.TryRemove(key, out _);
        }

        if (expiredKeys.Count > 0)
        {
            _logger.LogDebug("Cleaned up {Count} expired rate limit entries", expiredKeys.Count);
        }
    }
}