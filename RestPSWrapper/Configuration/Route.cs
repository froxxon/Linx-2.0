namespace RestPSWrapper.Configuration;

/// <summary>
/// Route configuration from Routes.json
/// </summary>
public class Route
{
    public string RequestType { get; set; } = string.Empty;
    public string RequestURL { get; set; } = string.Empty;
    public string RequestCommand { get; set; } = string.Empty;
}
