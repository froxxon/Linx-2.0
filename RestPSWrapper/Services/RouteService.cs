using System.Text.Json;
using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;
using Route = RestPSWrapper.Configuration.Route;

namespace RestPSWrapper.Services;

public class RouteService : IRouteService
{
    private readonly ILogger<RouteService> _logger;
    private readonly ScriptVariablesConfig _config;
    private List<Route> _routes = new();
    private readonly object _lock = new();
    private FileSystemWatcher? _watcher;

    public RouteService(ILogger<RouteService> logger, IOptions<ScriptVariablesConfig> options)
    {
        _logger = logger;
        _config = options.Value;
        ReloadRoutes();
        InitializeRouteFileWatcher();
    }

    public Route? FindRoute(string requestType, string requestURL)
    {
        if (string.IsNullOrEmpty(requestType) || string.IsNullOrEmpty(requestURL))
        {
            _logger.LogWarning("Invalid route lookup: requestType={Type}, requestURL={URL}", requestType, requestURL);
            return null;
        }

        lock (_lock)
        {
            return _routes.FirstOrDefault(r => 
                r.RequestType.Equals(requestType, StringComparison.OrdinalIgnoreCase) &&
                r.RequestURL.Equals(requestURL, StringComparison.OrdinalIgnoreCase));
        }
    }

    public void ReloadRoutes()
    {
        try
        {
            if (string.IsNullOrEmpty(_config.RoutesFilePath))
            {
                _logger.LogError("RoutesFilePath is not configured");
                return;
            }

            if (!File.Exists(_config.RoutesFilePath))
            {
                _logger.LogError("Routes file not found at {RoutesPath}", _config.RoutesFilePath);
                return;
            }

            var json = File.ReadAllText(_config.RoutesFilePath);
            var routes = JsonSerializer.Deserialize<List<Route>>(json) ?? new();

            lock (_lock)
            {
                _routes = routes;
            }

            _logger.LogInformation("Routes loaded: {RouteCount} routes", _routes.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading routes from {RoutesPath}", _config.RoutesFilePath);
        }
    }

    private void InitializeRouteFileWatcher()
    {
        try
        {
            if (string.IsNullOrEmpty(_config.RoutesFilePath))
            {
                _logger.LogWarning("Route file watcher not initialized: RoutesFilePath not configured");
                return;
            }

            var routeDirectory = Path.GetDirectoryName(_config.RoutesFilePath);
            var routeFileName = Path.GetFileName(_config.RoutesFilePath);

            if (string.IsNullOrEmpty(routeDirectory) || string.IsNullOrEmpty(routeFileName))
            {
                _logger.LogWarning("Invalid route file path for watcher: {Path}", _config.RoutesFilePath);
                return;
            }

            _watcher = new FileSystemWatcher(routeDirectory)
            {
                Filter = routeFileName,
                NotifyFilter = NotifyFilters.LastWrite
            };

            _watcher.Changed += OnRouteFileChanged;
            _watcher.EnableRaisingEvents = true;
            _logger.LogInformation("Route file watcher initialized for {Path}", _config.RoutesFilePath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error initializing route file watcher");
        }
    }

    private void OnRouteFileChanged(object sender, FileSystemEventArgs e)
    {
        _logger.LogInformation("Route file changed, reloading routes");
        // Add small delay to ensure file is fully written
        Task.Delay(100).ContinueWith(_ => ReloadRoutes());
    }
}