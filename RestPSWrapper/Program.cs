using System.Security.Cryptography;
using Serilog;
using Serilog.Events;
using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.ResponseCompression;
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

// Add CORS - Accept all origins but validate with middleware
builder.Services.AddCors(options =>
{
    var allowedMethods = string.IsNullOrEmpty(scriptVariables.AccessControlAllowMethods)
        ? new[] { "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS" }
        : scriptVariables.AccessControlAllowMethods.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(m => m.Trim())
            .ToArray();

    options.AddDefaultPolicy(policy =>
    {
        policy
            .SetIsOriginAllowed(origin => true)  // Accept any origin (validated in middleware)
            .WithMethods(allowedMethods)
            .AllowAnyHeader()
            .AllowCredentials();
    });
});

builder.Services.AddControllers(options =>
{
    options.Filters.AddService<IAsyncActionFilter>();
});

var app = builder.Build();

// Use middleware in correct order (critical for security)
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

            Log.Information("Loaded dynamic variable: {Key} = {Value}", key, value);
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