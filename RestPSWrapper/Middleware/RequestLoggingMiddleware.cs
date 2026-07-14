using System.Security.Claims;

namespace RestPSWrapper.Middleware;

public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public RequestLoggingMiddleware(RequestDelegate next, ILogger<RequestLoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        // SECURITY FIX #5: Validate user authentication before logging
        var userName = "Unknown";
        if (context.User?.Identity?.IsAuthenticated == true)
        {
            userName = context.User.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value ?? "Authenticated (No Name Claim)";
        }
        else
        {
            _logger.LogWarning("Unauthenticated request: {Method} {Path}", context.Request.Method, context.Request.Path);
        }

        var method = context.Request.Method;
        var path = context.Request.Path;
        var query = context.Request.QueryString;

        _logger.LogInformation(
            "New Request - User: {User}, Method: {Method}, Path: {Path}{Query}, ContentLength: {ContentLength}",
            userName, method, path, query, context.Request.ContentLength);

        // Enable buffering so body can be read multiple times
        if (method != "GET" && method != "HEAD" && method != "DELETE" && context.Request.ContentLength > 0)
        {
            context.Request.EnableBuffering();
        }

        await _next(context);

        stopwatch.Stop();
        _logger.LogInformation(
            "Response sent - User: {User}, StatusCode: {StatusCode}, Duration: {Duration}ms",
            userName, context.Response.StatusCode, stopwatch.ElapsedMilliseconds);
    }
}