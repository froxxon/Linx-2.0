using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;
using System.Net.Http;

namespace RestPSWrapper.Services;

public class PowerShellProxyService : IPowerShellProxyService
{
    private readonly ILogger<PowerShellProxyService> _logger;
    private readonly ScriptVariablesConfig _config;
    private readonly HttpClient _httpClient;
    private readonly Uri _backendBaseUri;

    public PowerShellProxyService(
        ILogger<PowerShellProxyService> logger,
        IOptions<ScriptVariablesConfig> options,
        HttpClient httpClient)
    {
        _logger = logger;
        _config = options.Value;
        _httpClient = httpClient;
        
        // Validate and parse PowerShellServiceUrl
        _backendBaseUri = ValidateBackendUrl(_config.PowerShellServiceUrl);
    }

    public async Task<(int StatusCode, byte[] Body, Dictionary<string, string> Headers)> ForwardRequestAsync(
        string method,
        string path,
        string? queryString,
        string? body,
        Dictionary<string, string>? userHeaders = null)
    {
        try
        {
            // Build URL from backend base URI
            var url = $"{_backendBaseUri.Scheme}://{_backendBaseUri.Host}:{_backendBaseUri.Port}{path}";

            if (!string.IsNullOrEmpty(queryString))
            {
                if (queryString.StartsWith("?"))
                {
                    url += queryString;
                }
                else
                {
                    url += $"?{queryString}";
                }
            }

            _logger.LogInformation("Forwarding {Method} request to {Url} for user {User}",
                method, url, userHeaders?.GetValueOrDefault("X-Authenticated-User") ?? "Unknown");

            using var request = new HttpRequestMessage(new HttpMethod(method), url);

            if (!string.IsNullOrEmpty(body))
            {
                request.Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");
            }

            if (userHeaders != null)
            {
                foreach (var header in userHeaders)
                {
                    request.Headers.Add(header.Key, header.Value);
                }
            }

            using var response = await _httpClient.SendAsync(request);

            // Read response as byte array to support both text and binary content (images, icons, PDFs, etc.)
            var responseBody = await response.Content.ReadAsByteArrayAsync();

            var responseHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (var header in response.Headers)
            {
                responseHeaders[header.Key] = string.Join(",", header.Value).Trim();
            }

            foreach (var header in response.Content.Headers)
            {
                responseHeaders[header.Key] = string.Join(",", header.Value).Trim();
            }

            _logger.LogInformation("Response: {StatusCode}, ContentType: {ContentType}, Size: {Size} bytes", 
                response.StatusCode, 
                responseHeaders.GetValueOrDefault("Content-Type", "unknown"),
                responseBody.Length);

            return ((int)response.StatusCode, responseBody, responseHeaders);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error forwarding request to PowerShell endpoint");
            var errorBytes = System.Text.Encoding.UTF8.GetBytes("Bad Gateway - Unable to connect to PowerShell endpoint");
            return (502, errorBytes, new(StringComparer.OrdinalIgnoreCase));
        }
    }

    /// <summary>
    /// Validate and parse the PowerShell backend service URL
    /// </summary>
    private Uri ValidateBackendUrl(string serviceUrl)
    {
        try
        {
            if (string.IsNullOrEmpty(serviceUrl))
            {
                throw new InvalidOperationException("PowerShellServiceUrl is required and cannot be empty");
            }

            var uri = new Uri(serviceUrl);

            // Validate scheme is HTTP or HTTPS
            if (uri.Scheme != "http" && uri.Scheme != "https")
            {
                throw new InvalidOperationException($"PowerShellServiceUrl scheme must be 'http' or 'https', got '{uri.Scheme}'");
            }

            _logger.LogInformation("PowerShell backend service configured: {Scheme}://{Host}:{Port}",
                uri.Scheme, uri.Host, uri.Port);

            return uri;
        }
        catch (UriFormatException ex)
        {
            throw new InvalidOperationException($"Invalid PowerShellServiceUrl format: '{serviceUrl}'", ex);
        }
    }
}