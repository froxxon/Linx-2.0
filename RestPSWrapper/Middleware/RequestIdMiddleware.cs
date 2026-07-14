using Serilog.Context;

namespace RestPSWrapper.Middleware;

/// <summary>
/// Middleware to add request ID correlation
/// Enables tracing requests across logs and responses
/// </summary>
public class RequestIdMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestIdMiddleware> _logger;

    public RequestIdMiddleware(RequestDelegate next, ILogger<RequestIdMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Generate or use existing request ID
        var requestId = context.Request.Headers["X-Request-ID"].FirstOrDefault() ?? Guid.NewGuid().ToString();
        context.Items["RequestId"] = requestId;

        // Add to response headers
        context.Response.Headers["X-Request-ID"] = requestId;

        // Add to logs (LogContext if using Serilog)
        using (LogContext.PushProperty("RequestId", requestId))
        {
            _logger.LogDebug("Request ID: {RequestId}", requestId);
            await _next(context);
        }
    }
}