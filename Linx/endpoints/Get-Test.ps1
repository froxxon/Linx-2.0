param(
	$RequestArgs,
	$Body,
	[string]$Type
)

# Simple test endpoint to verify parameter passing works
$HTML = [System.Text.StringBuilder]::new()
[void]$HTML.AppendLine("<!DOCTYPE html><html><head><title>Test</title></head><body>")
[void]$HTML.AppendLine("<h1>Test Endpoint</h1>")
[void]$HTML.AppendLine("<p><strong>Type parameter:</strong> $Type</p>")
[void]$HTML.AppendLine("<p><strong>RequestArgs:</strong> $RequestArgs</p>")
[void]$HTML.AppendLine("<p><strong>Body length:</strong> $($Body.Length)</p>")
[void]$HTML.AppendLine("</body></html>")

return $HTML.ToString()
