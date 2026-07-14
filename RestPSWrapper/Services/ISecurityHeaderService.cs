using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;

namespace RestPSWrapper.Services;

public interface ISecurityHeaderService
{
    /// <summary>
    /// Apply security headers from appsettings.json configuration and return the list of protected header names
    /// </summary>
    /// <returns>HashSet of header names that should be protected from overwriting</returns>
    HashSet<string> ApplySecurityHeaders(HttpResponse response, string? nonce = null);
}
