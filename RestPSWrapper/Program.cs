using System.Security.Cryptography;
using System.Net;
using Serilog;
using Serilog.Events;
using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Options;
using Polly;
using Polly.CircuitBreaker;
using Polly.Extensions.Http;
using RestPSWrapper.Configuration;
using RestPSWrapper.Filters;
using RestPSWrapper.Middleware;
using RestPSWrapper.Services;

var builder = WebApplication.CreateBuilder(args);

// Load and validate configuration
var scriptVariables = LoadAndValidateConfig(builder.Configuration);

// Validate routes file exists on startup
ValidateRoutesFile(scriptVariables.RoutesFilePath);

// Configure Serilog
var logPath = Path.Combine(scriptVariables.LogDirectory, "RestPS.log");
var logDirectory = Path.GetDirectoryName(logPath);
if (!Directory.Exists(logDirectory))
{
    Directory.CreateDirectory(logDirectory!);
}

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Is(ParseLogLevel(scriptVariables.LogLevel))
    .WriteTo.Console()
    .WriteTo.File(logPath, rollingInterval: RollingInterval.Day, retainedFileCountLimit: 30)
    .CreateLogger();

builder.Host.UseSerilog();

// Configure request buffering
builder.Services.Configure<IISServerOptions>(options =>
{
    options.AllowSynchronousIO = true;
    options.MaxRequestBodySize = scriptVariables.MaxRequestBodySizeBytes > 0 
        ? scriptVariables.MaxRequestBodySizeBytes 
        : null;
});

// Add services
// Register the already-processed configuration instance directly
// This avoids manual property copying and ensures PSVars are included
builder.Services.AddSingleton(scriptVariables);
builder.Services.AddSingleton<IOptions<ScriptVariablesConfig>>(sp => 
    Options.Create(sp.GetRequiredService<ScriptVariablesConfig>()));

// Log security configuration for verification
Log.Information("Security Configuration:");
Log.Information("  HTMLContentSecurityPolicy: {CSP}", scriptVariables.HTMLContentSecurityPolicy);
Log.Information("  HTMLCacheControl: {CacheControl}", scriptVariables.HTMLCacheControl);
Log.Information("  RequireCsrfToken: {RequireCsrf}", scriptVariables.RequireCsrfToken);
Log.Information("  EnforceCorsOriginValidation: {EnforceCors}", scriptVariables.EnforceCorsOriginValidation);

// Log resolved paths for verification
Log.Information("Resolved Paths:");
Log.Information("  ScriptPath: {ScriptPath}", scriptVariables.ScriptPath);
Log.Information("  RoutesFilePath: {RoutesFilePath}", scriptVariables.RoutesFilePath);
Log.Information("  LogDirectory: {LogDirectory}", scriptVariables.LogDirectory);
Log.Information("  PowerShellServiceUrl: {PowerShellServiceUrl}", scriptVariables.PowerShellServiceUrl);

builder.Services.AddSingleton<IRouteService, RouteService>();
builder.Services.AddSingleton<ISecurityHeaderService, SecurityHeaderService>();
builder.Services.AddSingleton<IUserContextService, UserContextService>();
builder.Services.AddSingleton<ISignatureService, SignatureService>();
builder.Services.AddSingleton<ICsrfTokenService, CsrfTokenService>();
builder.Services.AddScoped<IAsyncActionFilter, AuditLoggingFilter>();

// Add authentication (Kerberos/Negotiate with IIS)
builder.Services.AddAuthentication(options =>
{
    options.DefaultScheme = "Negotiate";
})
    .AddNegotiate();

builder.Services.AddAuthorization();

// Add HttpClient with circuit breaker resilience using Polly v8.x pattern
var circuitBreakerPolicy = HttpPolicyExtensions
    .HandleTransientHttpError()
    .OrResult(r => r.StatusCode == System.Net.HttpStatusCode.TooManyRequests)
    .CircuitBreakerAsync(
        handledEventsAllowedBeforeBreaking: 3,
        durationOfBreak: TimeSpan.FromSeconds(30),
        onBreak: (outcome, timespan) =>
        {
            Log.Warning("Circuit breaker opened for PowerShell endpoint. Will retry in {Timespan}ms", timespan.TotalMilliseconds);
        },
        onReset: () =>
        {
            Log.Information("Circuit breaker reset for PowerShell endpoint");
        });

var retryPolicy = HttpPolicyExtensions
    .HandleTransientHttpError()
    .WaitAndRetryAsync(
        retryCount: 2,
        sleepDurationProvider: retryAttempt =>
            TimeSpan.FromMilliseconds(Math.Pow(2, retryAttempt) * 100),
        onRetry: (outcome, timespan, retryCount, context) =>
        {
            Log.Warning("Retry {RetryCount} for PowerShell endpoint after {Delay}ms", retryCount, timespan.TotalMilliseconds);
        });

builder.Services.AddHttpClient<IPowerShellProxyService, PowerShellProxyService>()
    .AddPolicyHandler(retryPolicy)
    .AddPolicyHandler(circuitBreakerPolicy)
    .ConfigureHttpClient(client =>
    {
        client.Timeout = TimeSpan.FromSeconds(30);
    });

// Add response compression
builder.Services.AddResponseCompression(options =>
{
    options.Providers.Add<GzipCompressionProvider>();
    options.Providers.Add<BrotliCompressionProvider>();
    options.MimeTypes = new[]
    {
        "application/json",
        "application/javascript",
        "text/css",
        "text/plain",
        "text/html",
        "application/xml"
    };
});

// Add CORS - Use explicit trusted origins when credentials are allowed
builder.Services.AddCors(options =>
{
    var allowedMethods = string.IsNullOrEmpty(scriptVariables.AccessControlAllowMethods)
        ? new[] { "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS" }
        : scriptVariables.AccessControlAllowMethods.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(m => m.Trim())
            .ToArray();

    // Parse trusted origins from configuration
    var trustedOrigins = string.IsNullOrEmpty(scriptVariables.TrustedOrigins)
        ? Array.Empty<string>()
        : scriptVariables.TrustedOrigins.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(o => o.Trim())
            .Where(o => !string.IsNullOrEmpty(o))
            .ToArray();

    options.AddDefaultPolicy(policy =>
    {
        // SECURITY FIX: Use explicit origins instead of SetIsOriginAllowed when using AllowCredentials
        // SetIsOriginAllowed(origin => true) + AllowCredentials() is a security risk
        if (trustedOrigins.Length > 0)
        {
            policy
                .WithOrigins(trustedOrigins)
                .WithMethods(allowedMethods)
                .AllowAnyHeader()
                .AllowCredentials();

            Log.Information("CORS configured with explicit trusted origins: {Origins}", string.Join(", ", trustedOrigins));
        }
        else
        {
            // Fallback: Accept any origin but validate in middleware (no credentials)
            // This is less secure but maintains backward compatibility
            policy
                .SetIsOriginAllowed(origin => true)
                .WithMethods(allowedMethods)
                .AllowAnyHeader();

            Log.Warning("CORS configured without trusted origins - credentials disabled. Configure TrustedOrigins for enhanced security.");
        }
    });
});

builder.Services.AddControllers(options =>
{
    options.Filters.AddService<IAsyncActionFilter>();
});

// Configure forwarded headers for proxy/IIS scenarios (rate limiting IP trust)
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;

    // Trust localhost and private networks (IIS, reverse proxies on same network)
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();

    // Trust localhost
    options.KnownProxies.Add(IPAddress.Loopback);
    options.KnownProxies.Add(IPAddress.IPv6Loopback);

    // Trust private network ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
    options.KnownNetworks.Add(new Microsoft.AspNetCore.HttpOverrides.IPNetwork(IPAddress.Parse("10.0.0.0"), 8));
    options.KnownNetworks.Add(new Microsoft.AspNetCore.HttpOverrides.IPNetwork(IPAddress.Parse("172.16.0.0"), 12));
    options.KnownNetworks.Add(new Microsoft.AspNetCore.HttpOverrides.IPNetwork(IPAddress.Parse("192.168.0.0"), 16));

    // Limit to 1 proxy hop for security (can be adjusted if more hops needed)
    options.ForwardLimit = 1;
});

var app = builder.Build();

// Use middleware in correct order (critical for security)
app.UseForwardedHeaders();  // MUST be first to process X-Forwarded-* headers
app.UseRouting();
app.UseResponseCompression();
app.UseCors();

// Security & Validation middleware (before auth)
app.UseMiddleware<GlobalExceptionHandlerMiddleware>();
app.UseMiddleware<RequestIdMiddleware>();
app.UseMiddleware<RequestSizeLimitMiddleware>();
app.UseMiddleware<RateLimitingMiddleware>();

// Authentication & Authorization
app.UseAuthentication();
app.UseAuthorization();

// Application middleware
app.UseMiddleware<RequestLoggingMiddleware>();
app.UseMiddleware<SecurityMiddleware>();  // Unified security: CSRF + Origin + Headers

app.MapControllers();

try
{
    Log.Information("Starting RestPS Wrapper on {URL}", scriptVariables.ListenerUrl);
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}

static ScriptVariablesConfig LoadAndValidateConfig(IConfiguration configuration)
{
    var config = configuration.GetSection("ScriptVariables").Get<ScriptVariablesConfig>()
        ?? throw new InvalidOperationException("ScriptVariables configuration not found");

    // Extract PSVar_ properties dynamically from configuration
    var scriptVariablesSection = configuration.GetSection("ScriptVariables");
    foreach (var child in scriptVariablesSection.GetChildren())
    {
        var key = child.Key;
        if (key.StartsWith("PSVar_", StringComparison.OrdinalIgnoreCase))
        {
            var value = child.Value ?? string.Empty;
            // Store with the exact original key from configuration (preserving case)
            // This key will be used for placeholder replacement in HTML: {{key}}
            // So if config has "PSVar_CompanyName", store as "PSVar_CompanyName"
            // If config has "psVar_Test", store as "psVar_Test"
            config.PSVars[key] = value;

            // SECURITY: Redact sensitive values from logs (never log PSVar values)
            Log.Information("Loaded dynamic variable: {Key} = [REDACTED]", key);
        }
    }

    // Expand environment variables in path configurations
    config.ScriptPath = ExpandEnvironmentVariables(config.ScriptPath);
    config.RoutesFilePath = ExpandEnvironmentVariables(config.RoutesFilePath);
    config.LogDirectory = ExpandEnvironmentVariables(config.LogDirectory);
    config.RequestSignatureSecret = ExpandEnvironmentVariables(config.RequestSignatureSecret);

    // Validate required paths
    if (string.IsNullOrEmpty(config.ScriptPath))
        throw new InvalidOperationException("ScriptPath is required");

    if (string.IsNullOrEmpty(config.RoutesFilePath))
        throw new InvalidOperationException("RoutesFilePath is required");

    if (string.IsNullOrEmpty(config.LogDirectory))
        throw new InvalidOperationException("LogDirectory is required");

    // SECURITY: Validate signature secret
    if (string.IsNullOrEmpty(config.RequestSignatureSecret))
        throw new InvalidOperationException("RequestSignatureSecret MUST be set to a secure random value. It cannot be empty.");

    // SECURITY: Never log the actual secret value
    Log.Information("RequestSignatureSecret: [CONFIGURED]");

    // SECURITY: Validate backend URL (accepted risk - localhost only recommended)
    if (!string.IsNullOrEmpty(config.PowerShellServiceUrl))
    {
        if (Uri.TryCreate(config.PowerShellServiceUrl, UriKind.Absolute, out var backendUri))
        {
            var isLocalhost = backendUri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
                              backendUri.Host.Equals("127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
                              backendUri.Host.Equals("::1", StringComparison.OrdinalIgnoreCase);

            if (!isLocalhost)
            {
                Log.Warning("SECURITY: PowerShellServiceUrl is configured to non-localhost backend: {Backend}. " +
                           "For production, prefer HTTPS and consider mTLS for enhanced security.", config.PowerShellServiceUrl);
            }
            else if (!backendUri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase))
            {
                Log.Information("Backend configured for localhost with HTTP: {Backend} (accepted risk for local development)", config.PowerShellServiceUrl);
            }
        }
    }

    return config;
}

static string ExpandEnvironmentVariables(string value)
{
    if (string.IsNullOrEmpty(value))
        return value;

    // Pattern: ${ENV_VAR:default_value} or ${ENV_VAR}
    var pattern = @"\$\{([^:}]+)(?::([^}]+))?\}";
    var result = System.Text.RegularExpressions.Regex.Replace(value, pattern, match =>
    {
        var envVarName = match.Groups[1].Value;
        var defaultValue = match.Groups[2].Success ? match.Groups[2].Value : string.Empty;

        var envValue = Environment.GetEnvironmentVariable(envVarName);
        return !string.IsNullOrEmpty(envValue) ? envValue : defaultValue;
    });

    return result;
}

static void ValidateRoutesFile(string routesFilePath)
{
    if (!File.Exists(routesFilePath))
    {
        throw new FileNotFoundException($"Routes file not found at '{routesFilePath}'. Please verify RoutesFilePath configuration.");
    }
    
    Log.Information("Routes file validated: {RoutesFilePath}", routesFilePath);
}

static LogEventLevel ParseLogLevel(string logLevel) => logLevel switch
{
    "TRACE" => LogEventLevel.Verbose,
    "DEBUG" => LogEventLevel.Debug,
    "INFO" => LogEventLevel.Information,
    "WARN" => LogEventLevel.Warning,
    "ERROR" => LogEventLevel.Error,
    "FATAL" => LogEventLevel.Fatal,
    _ => LogEventLevel.Information
};