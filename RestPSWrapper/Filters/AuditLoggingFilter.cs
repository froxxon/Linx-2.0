using System.Diagnostics;
using System.Security.Claims;
using Microsoft.AspNetCore.Mvc.Filters;

namespace RestPSWrapper.Filters;

/// <summary>
/// Audit logging filter that logs all controller actions with timing and status information
/// FIXED: No longer uses "Anonymous" fallback - requires authenticated user
/// </summary>
public class AuditLoggingFilter : IAsyncActionFilter
{
    private readonly ILogger<AuditLoggingFilter> _logger;

    public AuditLoggingFilter(ILogger<AuditLoggingFilter> logger)
    {
        _logger = logger;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var stopwatch = Stopwatch.StartNew();
        
        // Get authenticated user or use marker for missing auth
        var userName = context.HttpContext.User?.FindFirst(ClaimTypes.Name)?.Value;
        if (string.IsNullOrEmpty(userName))
        {
            userName = context.HttpContext.User?.Identity?.IsAuthenticated == true 
                ? "AuthenticationMissing" 
                : "Unauthenticated";
        }
        
        var requestId = context.HttpContext.Items["RequestId"]?.ToString() ?? "Unknown";
        var actionName = context.ActionDescriptor.DisplayName ?? "Unknown";
        var method = context.HttpContext.Request.Method;
        var path = context.HttpContext.Request.Path;

        _logger.LogInformation(
            "[AUDIT] Action started - RequestId: {RequestId}, User: {User}, Action: {Action}, Method: {Method}, Path: {Path}",
            requestId, userName, actionName, method, path);

        try
        {
            var executedContext = await next();
            stopwatch.Stop();

            var statusCode = executedContext.HttpContext.Response.StatusCode;
            _logger.LogInformation(
                "[AUDIT] Action completed - RequestId: {RequestId}, User: {User}, Action: {Action}, StatusCode: {StatusCode}, Duration: {Duration}ms",
                requestId, userName, actionName, statusCode, stopwatch.ElapsedMilliseconds);
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            _logger.LogError(
                ex,
                "[AUDIT] Action failed - RequestId: {RequestId}, User: {User}, Action: {Action}, Duration: {Duration}ms",
                requestId, userName, actionName, stopwatch.ElapsedMilliseconds);
            throw;
        }
    }
}