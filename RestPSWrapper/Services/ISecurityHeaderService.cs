using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;

namespace RestPSWrapper.Services;

public interface ISecurityHeaderService
{
    void ApplySecurityHeaders(HttpResponse response, string? nonce = null);
}
