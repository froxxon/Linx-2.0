using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RestPSWrapper.Services;

namespace RestPSWrapper.Controllers;

/// <summary>
/// Controller for CSRF token management
/// Provides endpoints for clients to obtain and manage CSRF tokens
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class CsrfController : ControllerBase
{
    private readonly ICsrfTokenService _csrfTokenService;
    private readonly ILogger<CsrfController> _logger;

    public CsrfController(ICsrfTokenService csrfTokenService, ILogger<CsrfController> logger)
    {
        _csrfTokenService = csrfTokenService;
        _logger = logger;
    }

    /// <summary>
    /// Get a CSRF token for the current session
    /// Clients should call this endpoint before making state-changing requests (POST/PUT/PATCH/DELETE)
    /// The token is returned both in the response body and in the X-CSRF-Token header
    /// </summary>
    /// <returns>JSON object containing the CSRF token</returns>
    [HttpGet("token")]
    public IActionResult GetToken()
    {
        // Get or create session ID (set by SecurityMiddleware)
        var sessionId = HttpContext.Items["SessionId"]?.ToString();

        if (string.IsNullOrEmpty(sessionId))
        {
            _logger.LogError("Session ID not found in HttpContext. Middleware may not be configured correctly.");
            return StatusCode(StatusCodes.Status500InternalServerError, new { error = "Session not initialized" });
        }

        // Generate token (already done by middleware, but we'll return it explicitly)
        // The middleware also sets it in response headers
        var token = Response.Headers["X-CSRF-Token"].ToString();

        if (string.IsNullOrEmpty(token))
        {
            _logger.LogWarning("CSRF token not found in response headers. Generating new token.");
            token = _csrfTokenService.GenerateToken(sessionId);
            Response.Headers["X-CSRF-Token"] = token;
        }

        _logger.LogDebug("CSRF token provided for session {SessionId}", sessionId);

        return Ok(new 
        { 
            token = token,
            headerName = "X-CSRF-Token",
            expiresIn = "3600 seconds",
            usage = "Include this token in the X-CSRF-Token header for POST/PUT/PATCH/DELETE requests"
        });
    }

    /// <summary>
    /// Invalidate the current session's CSRF token (logout/security)
    /// Useful when a user logs out or when you want to force token regeneration
    /// </summary>
    [HttpPost("invalidate")]
    public IActionResult InvalidateToken()
    {
        var sessionId = HttpContext.Items["SessionId"]?.ToString();

        if (string.IsNullOrEmpty(sessionId))
        {
            return BadRequest(new { error = "No active session" });
        }

        _csrfTokenService.InvalidateSession(sessionId);
        _logger.LogInformation("CSRF token invalidated for session {SessionId}", sessionId);

        return Ok(new { message = "CSRF token invalidated. Request a new token before making state-changing requests." });
    }

    /// <summary>
    /// Health check endpoint to verify CSRF service is operational
    /// </summary>
    [HttpGet("health")]
    [AllowAnonymous]
    public IActionResult Health()
    {
        return Ok(new 
        { 
            status = "healthy",
            service = "CSRF Token Service",
            timestamp = DateTime.UtcNow
        });
    }
}
