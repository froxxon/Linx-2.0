using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;

namespace RestPSWrapper.Middleware;

/// <summary>
/// Middleware to enforce request body size limits
/// Prevents large payload attacks and resource exhaustion
/// </summary>
public class RequestSizeLimitMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestSizeLimitMiddleware> _logger;
    private readonly long _maxRequestBodySize;

    public RequestSizeLimitMiddleware(
        RequestDelegate next,
        ILogger<RequestSizeLimitMiddleware> logger,
        IOptions<ScriptVariablesConfig> options)
    {
        _next = next;
        _logger = logger;
        _maxRequestBodySize = options.Value.MaxRequestBodySizeBytes;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Only check for requests with body (POST, PUT, PATCH)
        if ((context.Request.Method == "POST" || context.Request.Method == "PUT" || context.Request.Method == "PATCH") &&
            context.Request.ContentLength.HasValue &&
            _maxRequestBodySize > 0 &&
            context.Request.ContentLength > _maxRequestBodySize)
        {
            var requestId = context.Items["RequestId"]?.ToString() ?? "Unknown";
            _logger.LogWarning(
                "Request rejected - body size {ContentLength} exceeds limit {MaxSize}. RequestId: {RequestId}, Path: {Path}",
                context.Request.ContentLength, _maxRequestBodySize, requestId, context.Request.Path);

            context.Response.StatusCode = StatusCodes.Status413PayloadTooLarge;
            context.Response.ContentType = "application/json";
            await context.Response.WriteAsJsonAsync(new
            {
                error = "Payload Too Large",
                maxSize = _maxRequestBodySize,
                requestId = requestId
            });
            return;
        }

        await _next(context);
    }
}