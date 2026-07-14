using System.Security.Claims;

namespace RestPSWrapper.Middleware;

/// <summary>
/// Global exception handler middleware
/// Catches unhandled exceptions and returns safe error responses
/// </summary>
public class GlobalExceptionHandlerMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<GlobalExceptionHandlerMiddleware> _logger;

    public GlobalExceptionHandlerMiddleware(RequestDelegate next, ILogger<GlobalExceptionHandlerMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var requestId = context.Items["RequestId"]?.ToString() ?? "Unknown";
        var userName = context.User?.FindFirst(ClaimTypes.Name)?.Value ?? "Unknown";

        try
        {
            await _next(context);
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogError(
                ex,
                "Invalid operation - RequestId: {RequestId}, User: {User}, Path: {Path}",
                requestId, userName, context.Request.Path);
            
            await WriteErrorResponse(context, StatusCodes.Status400BadRequest, "Invalid request", requestId);
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogWarning(
                ex,
                "Unauthorized access - RequestId: {RequestId}, User: {User}, Path: {Path}",
                requestId, userName, context.Request.Path);
            
            await WriteErrorResponse(context, StatusCodes.Status403Forbidden, "Access denied", requestId);
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Unhandled exception - RequestId: {RequestId}, User: {User}, Path: {Path}, Method: {Method}",
                requestId, userName, context.Request.Path, context.Request.Method);
            
            await WriteErrorResponse(context, StatusCodes.Status500InternalServerError, "Internal server error", requestId);
        }
    }

    private static Task WriteErrorResponse(HttpContext context, int statusCode, string message, string requestId)
    {
        if (context.Response.HasStarted)
        {
            return Task.CompletedTask;
        }

        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";

        return context.Response.WriteAsJsonAsync(new
        {
            error = message,
            requestId = requestId,
            timestamp = DateTime.UtcNow.ToString("o")
        });
    }
}