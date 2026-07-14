namespace RestPSWrapper.Services;

public interface IPowerShellProxyService
{
    Task<(int StatusCode, byte[] Body, Dictionary<string, string> Headers)> ForwardRequestAsync(
        string method,
        string path,
        string? queryString,
        string? body,
        Dictionary<string, string>? userHeaders = null);
}
