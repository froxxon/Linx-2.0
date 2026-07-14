using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;

namespace RestPSWrapper.Services;

public interface ISignatureService
{
    string GenerateSignature(string data);
    bool VerifySignature(string data, string signature);
}

public class SignatureService : ISignatureService
{
    private readonly ScriptVariablesConfig _config;
    private readonly ILogger<SignatureService> _logger;

    public SignatureService(IOptions<ScriptVariablesConfig> options, ILogger<SignatureService> logger)
    {
        _config = options.Value;
        _logger = logger;
    }

    public string GenerateSignature(string data)
    {
        try
        {
            using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(_config.RequestSignatureSecret));
            var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(data));
            return Convert.ToBase64String(hash);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error generating signature");
            throw;
        }
    }

    public bool VerifySignature(string data, string signature)
    {
        try
        {
            var expectedSignature = GenerateSignature(data);
            return expectedSignature.Equals(signature, StringComparison.Ordinal);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error verifying signature");
            return false;
        }
    }
}