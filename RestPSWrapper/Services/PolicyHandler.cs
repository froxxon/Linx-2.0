using System.Net.Http;
using Polly;

namespace RestPSWrapper.Services;

public class PolicyHandler : DelegatingHandler
{
    private readonly IAsyncPolicy<HttpResponseMessage> _policy;

    public PolicyHandler(IAsyncPolicy<HttpResponseMessage> policy)
    {
        _policy = policy;
    }

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        return _policy.ExecuteAsync((ct) => base.SendAsync(request, ct), cancellationToken);
    }
}
