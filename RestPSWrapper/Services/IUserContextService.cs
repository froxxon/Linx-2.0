using System.Security.Claims;
using System.Security.Principal;
using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;

namespace RestPSWrapper.Services;

public interface IUserContextService
{
    Task<Dictionary<string, string>> GetUserHeadersAsync(ClaimsPrincipal user);
}

public class UserContextService : IUserContextService
{
    private readonly ILogger<UserContextService> _logger;
    private readonly ScriptVariablesConfig _config;

    public UserContextService(ILogger<UserContextService> logger, IOptions<ScriptVariablesConfig> options)
    {
        _logger = logger;
        _config = options.Value;
    }

    public async Task<Dictionary<string, string>> GetUserHeadersAsync(ClaimsPrincipal user)
    {
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            // SECURITY FIX #2: Validate user claims exist - don't fall back to "Anonymous"
            if (user?.Identity == null || !user.Identity.IsAuthenticated)
            {
                _logger.LogWarning("Unauthenticated request detected - user identity is null or not authenticated");
                throw new InvalidOperationException("User authentication is required");
            }

            var userName = user.FindFirst(ClaimTypes.Name)?.Value;
            if (string.IsNullOrEmpty(userName))
            {
                _logger.LogWarning("User authentication claim missing - authentication may have failed");
                throw new InvalidOperationException("User name claim not found in authentication token");
            }

            headers["X-Authenticated-User"] = userName;
            _logger.LogDebug("User context extracted for: {User}", userName);

            // SECURITY FIX #5: Validate identity type before casting
            if (user.Identity is WindowsIdentity windowsIdentity && _config.IncludeUserSID)
            {
                var sid = windowsIdentity.User?.Value;
                if (!string.IsNullOrEmpty(sid))
                {
                    headers["X-User-SID"] = sid;
                    _logger.LogDebug("User SID included: {SID}", sid);
                }
            }

            // Optional: Query Active Directory for additional info
            if (_config.IncludeUserEmail || _config.IncludeUserDisplayName || _config.IncludeUserGroups)
            {
                await EnrichUserFromActiveDirectoryAsync(userName, headers);
            }
        }
        catch (InvalidOperationException ex)
        {
            // Re-throw auth failures - don't mask them
            _logger.LogError(ex, "Authentication validation failed");
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error extracting user context");
            throw;
        }

        return headers;
    }

    private async Task EnrichUserFromActiveDirectoryAsync(string userName, Dictionary<string, string> headers)
    {
        try
        {
            // Extract domain and user
            var parts = userName.Split('\\');
            if (parts.Length != 2)
            {
                _logger.LogWarning("Invalid username format for AD lookup: {User}", userName);
                return;
            }

            var domain = parts[0];
            var samAccountName = parts[1];

#if DEBUG
            // Placeholder for development - just log what we would do
            _logger.LogDebug("[DEBUG] Would query AD for user {Domain}\\{User}", domain, samAccountName);
            await Task.CompletedTask;
#else
            // Production Active Directory implementation
            // SECURITY FIX #3: Use LDAP filter escaping to prevent LDAP injection
            // Uncomment the code below and implement according to your needs:
            /*
            try
            {
                using (var entry = new System.DirectoryServices.DirectoryEntry($"LDAP://{domain}"))
                {
                    using (var searcher = new System.DirectoryServices.DirectorySearcher(entry))
                    {
                        // IMPORTANT: Escape the samAccountName to prevent LDAP injection attacks
                        var escapedAccountName = EscapeLdapFilterValue(samAccountName);
                        searcher.Filter = $"(sAMAccountName={escapedAccountName})";
                        searcher.PropertiesToLoad.AddRange(new[] { "mail", "displayName", "memberOf" });
                        searcher.SizeLimit = 1; // Only retrieve first result
                        
                        var result = searcher.FindOne();
                        if (result != null)
                        {
                            if (_config.IncludeUserEmail && result.Properties.Contains("mail"))
                                headers["X-User-Email"] = result.Properties["mail"][0]?.ToString() ?? string.Empty;
                            
                            if (_config.IncludeUserDisplayName && result.Properties.Contains("displayName"))
                                headers["X-User-Display-Name"] = result.Properties["displayName"][0]?.ToString() ?? string.Empty;
                            
                            if (_config.IncludeUserGroups && result.Properties.Contains("memberOf"))
                                headers["X-User-Groups"] = string.Join(",", result.Properties["memberOf"].Cast<string>());
                        }
                    }
                }
            }
            catch (System.DirectoryServices.DirectoryServicesCOMException ex)
            {
                _logger.LogError(ex, "Active Directory service error for domain {Domain}", domain);
            }
            */
            await Task.CompletedTask;
#endif
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error enriching user from Active Directory");
            // Don't throw - AD enrichment is optional
        }
    }

    /// <summary>
    /// SECURITY FIX #3: Escape LDAP filter values to prevent LDAP injection attacks
    /// Based on RFC 4515: LDAP: The Protocol
    /// </summary>
    private static string EscapeLdapFilterValue(string value)
    {
        if (string.IsNullOrEmpty(value))
            return value;

        var sb = new System.Text.StringBuilder();
        foreach (char c in value)
        {
            switch (c)
            {
                case '*':
                    sb.Append("\\2a");
                    break;
                case '(':
                    sb.Append("\\28");
                    break;
                case ')':
                    sb.Append("\\29");
                    break;
                case '\\':
                    sb.Append("\\5c");
                    break;
                case '/':
                    sb.Append("\\2f");
                    break;
                case (char)0:
                    sb.Append("\\00");
                    break;
                default:
                    sb.Append(c);
                    break;
            }
        }
        return sb.ToString();
    }
}