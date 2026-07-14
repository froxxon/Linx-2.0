using RestPSWrapper.Configuration;
using Route = RestPSWrapper.Configuration.Route;

namespace RestPSWrapper.Services;

public interface IRouteService
{
    Route? FindRoute(string requestType, string requestURL);
    void ReloadRoutes();
}
