using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;

namespace RestPSWrapper.Services;

public interface ICsrfTokenService
{
    /// <summary>Generate a new CSRF token</summary>
    string GenerateToken(string sessionId);
    
    /// <summary>Validate a CSRF token</summary>
    bool ValidateToken(string sessionId, string token);
    
    /// <summary>Invalidate all tokens for a session (logout)</summary>
    void InvalidateSession(string sessionId);
}

public class CsrfTokenService : ICsrfTokenService
{
    private readonly ILogger<CsrfTokenService> _logger;
    private readonly ScriptVariablesConfig _config;
    
    // Thread-safe storage of active tokens: sessionId -> (token, expirationTime)
    private readonly ConcurrentDictionary<string, (string token, DateTime expiration)> _tokenStore = new();
    
    // Timer for cleanup of expired tokens
    private readonly Timer _cleanupTimer;

    public CsrfTokenService(ILogger<CsrfTokenService> logger, IOptions<ScriptVariablesConfig> options)
    {
        _logger = logger;
        _config = options.Value;
        
        // Start background cleanup every 5 minutes
        _cleanupTimer = new Timer(
            callback: _ => CleanupExpiredTokens(),
            state: null,
            dueTime: TimeSpan.FromMinutes(5),
            period: TimeSpan.FromMinutes(5));
    }

    public string GenerateToken(string sessionId)
    {
        if (string.IsNullOrEmpty(sessionId))
        {
            throw new ArgumentException("Session ID cannot be null or empty", nameof(sessionId));
        }

        // Generate cryptographically secure random token (32 bytes = 256 bits)
        // Modern .NET provides static method, no using statement needed
        var tokenBytes = RandomNumberGenerator.GetBytes(32);

        var token = Convert.ToBase64String(tokenBytes);
        var expiration = DateTime.UtcNow.AddSeconds(_config.CsrfTokenExpirationSeconds);

        // Store or replace existing token for this session
        _tokenStore[sessionId] = (token, expiration);

        _logger.LogDebug("CSRF token generated for session {SessionId}, expires in {ExpirationSeconds}s", 
            sessionId, _config.CsrfTokenExpirationSeconds);

        return token;
    }

    public bool ValidateToken(string sessionId, string token)
    {
        if (string.IsNullOrEmpty(sessionId) || string.IsNullOrEmpty(token))
        {
            _logger.LogWarning("CSRF token validation failed: missing sessionId or token");
            return false;
        }

        if (!_tokenStore.TryGetValue(sessionId, out var storedToken))
        {
            _logger.LogWarning("CSRF token validation failed: no token found for session {SessionId}", sessionId);
            return false;
        }

        // Check expiration
        if (DateTime.UtcNow > storedToken.expiration)
        {
            _logger.LogWarning("CSRF token validation failed: token expired for session {SessionId}", sessionId);
            _tokenStore.TryRemove(sessionId, out _);
            return false;
        }

        // Timing-safe comparison to prevent timing attacks
        var isValid = TimingSafeCompare(token, storedToken.token);
        
        if (!isValid)
        {
            _logger.LogWarning("CSRF token validation failed: token mismatch for session {SessionId}", sessionId);
            return false;
        }

        _logger.LogDebug("CSRF token validated successfully for session {SessionId}", sessionId);
        return true;
    }

    public void InvalidateSession(string sessionId)
    {
        if (_tokenStore.TryRemove(sessionId, out _))
        {
            _logger.LogInformation("CSRF tokens invalidated for session {SessionId}", sessionId);
        }
    }

    /// <summary>
    /// Timing-safe string comparison to prevent timing attacks
    /// </summary>
    private static bool TimingSafeCompare(string a, string b)
    {
        // Use constant-time comparison
        var aBytes = Encoding.UTF8.GetBytes(a);
        var bBytes = Encoding.UTF8.GetBytes(b);
        
        uint result = (uint)aBytes.Length ^ (uint)bBytes.Length;
        
        for (int i = 0; i < Math.Min(aBytes.Length, bBytes.Length); i++)
        {
            result |= (uint)(aBytes[i] ^ bBytes[i]);
        }
        
        return result == 0;
    }

    /// <summary>
    /// Remove expired tokens from the store
    /// </summary>
    private void CleanupExpiredTokens()
    {
        var now = DateTime.UtcNow;
        var expiredKeys = _tokenStore
            .Where(kvp => kvp.Value.expiration < now)
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var key in expiredKeys)
        {
            _tokenStore.TryRemove(key, out _);
        }

        if (expiredKeys.Count > 0)
        {
            _logger.LogDebug("Cleaned up {ExpiredTokenCount} expired CSRF tokens", expiredKeys.Count);
        }
    }
}