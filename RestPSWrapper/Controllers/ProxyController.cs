using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;
using RestPSWrapper.Services;

namespace RestPSWrapper.Controllers;

[ApiController]
[Authorize]
public class ProxyController : ControllerBase
{
    private readonly IPowerShellProxyService _proxyService;
    private readonly IRouteService _routeService;
    private readonly IUserContextService _userContextService;
    private readonly ISignatureService _signatureService;
    private readonly ILogger<ProxyController> _logger;
    private readonly ScriptVariablesConfig _config;

    public ProxyController(
        IPowerShellProxyService proxyService,
        IRouteService routeService,
        IUserContextService userContextService,
        ISignatureService signatureService,
        ILogger<ProxyController> logger,
        IOptions<ScriptVariablesConfig> options)
    {
        _proxyService = proxyService;
        _routeService = routeService;
        _userContextService = userContextService;
        _signatureService = signatureService;
        _logger = logger;
        _config = options.Value;
    }

    [HttpGet("{**path}")]
    [HttpPost("{**path}")]
    [HttpPut("{**path}")]
    [HttpDelete("{**path}")]
    [HttpPatch("{**path}")]
    public async Task<IActionResult> Proxy(string? path)
    {
        path = "/" + (path ?? string.Empty);

        var route = _routeService.FindRoute(Request.Method, path);
        if (route == null)
        {
            _logger.LogWarning("No matching route found for {Method} {Path}", Request.Method, path);
            return NotFound("No matching route found");
        }

        var body = string.Empty;
        
        // Read request body for POST, PUT, PATCH (not GET, DELETE, HEAD)
        if ((Request.Method == "POST" || Request.Method == "PUT" || Request.Method == "PATCH")
            && (Request.ContentLength > 0 || Request.HasFormContentType))
        {
            try
            {
                // Ensure body can be read multiple times
                Request.EnableBuffering();
                using var reader = new StreamReader(Request.Body, System.Text.Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
                body = await reader.ReadToEndAsync();
                Request.Body.Position = 0; // Reset for potential reuse
                _logger.LogDebug("Read request body: {BodyLength} bytes", body.Length);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reading request body");
                return BadRequest("Failed to read request body");
            }
        }

        // Get user context and create secure headers
        var userHeaders = await _userContextService.GetUserHeadersAsync(User);
        var userName = userHeaders.GetValueOrDefault("X-Authenticated-User") ?? "Unknown";
        
        // SECURITY FIX #6: Include body length in signature to prevent replay attacks on similar requests
        // Also handle null/empty bodies distinctly
        var bodyForSignature = string.IsNullOrEmpty(body) ? "[EMPTY]" : body;
        var bodyLength = body?.Length ?? 0;
        var signatureData = $"{userName}|{Request.Method}|{path}|{bodyLength}|{bodyForSignature}";
        var signature = _signatureService.GenerateSignature(signatureData);
        userHeaders["X-Request-Signature"] = signature;

        _logger.LogInformation("Proxying {Method} {Path} for user {User} with {BodyLength} bytes",
            Request.Method, path, userName, body.Length);

        // Forward request to PowerShell backend
        var (statusCode, responseBody, headers) = await _proxyService.ForwardRequestAsync(
            Request.Method,
            path,
            Request.QueryString.Value,
            body,
            userHeaders);

        // Forward all response headers except Transfer-Encoding and Content-Type (handled separately)
        foreach (var header in headers)
        {
            if (header.Key.Equals("Transfer-Encoding", StringComparison.OrdinalIgnoreCase) ||
                header.Key.Equals("Content-Type", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            try
            {
                Response.Headers[header.Key] = header.Value;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to set response header {HeaderKey}", header.Key);
            }
        }

        // Get Content-Type from backend response, or infer from path
        var contentType = headers.TryGetValue("Content-Type", out var ct) 
            ? ct 
            : InferContentType(path);

        Response.StatusCode = statusCode;

        // Determine if content is binary based on Content-Type
        var isBinary = IsBinaryContentType(contentType);

        _logger.LogInformation("Proxy response: {StatusCode}, ContentType: {ContentType}, Binary: {IsBinary}, Size: {Size} bytes", 
            statusCode, contentType, isBinary, responseBody.Length);

        // Return binary data directly for images, icons, PDFs, etc.
        if (isBinary)
        {
            return File(responseBody, contentType);
        }

        // For text content, convert bytes to string
        var responseText = System.Text.Encoding.UTF8.GetString(responseBody);

        // Replace placeholders in HTML/text responses only if there are any
        // Early exit if no placeholders to replace
        if (responseText.Contains("{{", StringComparison.Ordinal) || 
            responseText.Contains("{nonce}", StringComparison.Ordinal) || 
            responseText.Contains("$nonce$", StringComparison.Ordinal))
        {
            // The nonce is generated by SecurityMiddleware and stored in HttpContext.Items
            var nonce = HttpContext.Items["CspNonce"]?.ToString();
            if (!string.IsNullOrEmpty(nonce))
            {
                // Replace various nonce placeholder formats that might be used in backend HTML
                responseText = responseText
                    .Replace("{{nonce}}", nonce, StringComparison.Ordinal)
                    .Replace("{nonce}", nonce, StringComparison.Ordinal)
                    .Replace("$nonce$", nonce, StringComparison.Ordinal);

                _logger.LogDebug("Replaced nonce placeholders in response with: {Nonce}", nonce);
            }

            // Replace dynamic PSVar_ placeholders (case-insensitive)
            foreach (var psVar in _config.PSVars)
            {
                var placeholder = $"{{{{{psVar.Key}}}}}";
                responseText = responseText.Replace(placeholder, psVar.Value, StringComparison.OrdinalIgnoreCase);
            }

            _logger.LogDebug("Replaced HTML placeholders: Nonce={HasNonce}, PSVars={PSVarCount}",
                nonce != null, _config.PSVars.Count);
        }

        return Content(responseText, contentType);
    }

    /// <summary>
    /// Infer content type from request path when backend doesn't provide it
    /// </summary>
    private static string InferContentType(string path)
    {
        if (path.EndsWith(".ico", StringComparison.OrdinalIgnoreCase))
            return "image/x-icon";
        if (path.EndsWith(".png", StringComparison.OrdinalIgnoreCase))
            return "image/png";
        if (path.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase) || 
            path.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase))
            return "image/jpeg";
        if (path.EndsWith(".gif", StringComparison.OrdinalIgnoreCase))
            return "image/gif";
        if (path.EndsWith(".svg", StringComparison.OrdinalIgnoreCase))
            return "image/svg+xml";
        if (path.EndsWith(".css", StringComparison.OrdinalIgnoreCase))
            return "text/css";
        if (path.EndsWith(".js", StringComparison.OrdinalIgnoreCase))
            return "application/javascript";
        if (path.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
            return "application/json";
        if (path.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase))
            return "application/pdf";

        // Default based on path pattern
        return path.StartsWith("/api/") ? "application/json" : "text/html";
    }

    /// <summary>
    /// Determine if Content-Type represents binary data that should not be decoded as text
    /// </summary>
    private static bool IsBinaryContentType(string contentType)
    {
        if (string.IsNullOrEmpty(contentType))
            return false;

        var type = contentType.Split(';')[0].Trim().ToLowerInvariant();

        return type switch
        {
            // Images
            "image/x-icon" => true,
            "image/png" => true,
            "image/jpeg" => true,
            "image/gif" => true,
            "image/webp" => true,
            "image/bmp" => true,
            "image/tiff" => true,

            // Documents
            "application/pdf" => true,
            "application/zip" => true,
            "application/octet-stream" => true,

            // Font files
            "font/woff" => true,
            "font/woff2" => true,
            "font/ttf" => true,
            "font/otf" => true,
            "application/font-woff" => true,
            "application/font-woff2" => true,

            // Audio/Video
            "audio/mpeg" => true,
            "audio/wav" => true,
            "video/mp4" => true,
            "video/webm" => true,

            _ => false
        };
    }
}