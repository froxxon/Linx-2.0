param ( $RequestArgs )

$faviconPath = "$($ScriptVariables.ScriptPath)/endpoints/favicon/favicon.ico"
if (Test-Path $faviconPath) {
	try {
		$bytes = [System.IO.File]::ReadAllBytes($faviconPath)
		$context.Response.ContentType = "image/x-icon"
		$context.Response.ContentLength64 = $bytes.Length
		$context.Response.StatusCode = 200
		$context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
		$context.Response.OutputStream.Close()
		return ""
	}
	catch {
		Write-Log -LogFile $ScriptVariables.LogFile -LogLevel "ERROR" -Message "Error serving favicon: $_"
		$context.Response.StatusCode = 500
		return "Error serving favicon"
	}
}
else {
	$context.Response.StatusCode = 404
	return "Favicon not found"
}