# Security Fix: Command Injection Vulnerability Removed

## Date: 2026-01-14

## Severity: HIGH

## Summary
Fixed a critical command injection vulnerability in `RestPSCustomModule.psm1` by removing the use of `Invoke-Expression` with user-controlled input.

## What Changed

### Before (VULNERABLE):
```powershell
else {
	# Execute Endpoint Command (No body allowed.)
	$Command = $RequestCommand + " " + $RequestArgs
	$CommandReturn = Invoke-Expression -Command "$Command" -ErrorAction SilentlyContinue
}
```

### After (SECURE):
```powershell
else {
	# SECURITY FIX: Removed Invoke-Expression to prevent command injection
	# All route commands must now be .ps1 scripts or static files
	Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType ERROR -Message "Invoke-RequestRouter: Route command '$RequestCommand' is not a .ps1 script or static file. Direct command execution is disabled for security."
	$script:StatusDescription = "Internal Server Error"
	$script:StatusCode = 500
	$CommandReturn = $null
}
```

## Security Improvements

1. **Removed Invoke-Expression**: Completely eliminated the dangerous `Invoke-Expression` code path that allowed arbitrary command execution
2. **Extension Whitelist**: Added explicit validation to only allow safe file types (.ps1, .css, .js, .html, etc.)
3. **Error Logging**: Routes with invalid extensions are logged and rejected with 500 error

## Breaking Change

⚠️ **IMPORTANT**: Routes that previously relied on direct command execution (non-.ps1 files) will no longer work.

### Required Migration

If you have routes in your Routes.json like:
```json
{
  "RequestType": "GET",
  "RequestURL": "/api/command",
  "RequestCommand": "Get-Process"
}
```

You **MUST** convert them to .ps1 scripts:

1. Create a new script file: `endpoints/Get-Process.ps1`
2. Add proper parameter validation:
```powershell
param(
	[Parameter(Mandatory=$false)]
	[string]$RequestArgs,

	[Parameter(Mandatory=$false)]
	[string]$Body
)

# Parse and validate RequestArgs safely
$params = @{}
if ($RequestArgs) {
	# Parse query string safely
	$queryParams = [System.Web.HttpUtility]::ParseQueryString($RequestArgs)
	foreach ($key in $queryParams.Keys) {
		$params[$key] = $queryParams[$key]
	}
}

# Your command logic here with validated parameters
Get-Process | Where-Object { $_.Name -like "*$($params['name'])*" } | Select-Object Name, Id, CPU
```

3. Update your route:
```json
{
  "RequestType": "GET",
  "RequestURL": "/api/process",
  "RequestCommand": "Get-Process.ps1"
}
```

## Why This Change Was Necessary

The previous implementation using `Invoke-Expression` allowed **arbitrary command injection**. An attacker could:

1. Send a request like: `/api/command?args=; Remove-Item C:\Important\File.txt -Force`
2. The args would be concatenated with the command and executed via `Invoke-Expression`
3. Any PowerShell command could be executed with the privileges of the service account

This is a **critical security vulnerability** that could lead to:
- Data theft
- System compromise
- Privilege escalation
- Denial of service

## Testing Your Routes

After upgrading, test each route:

1. Routes using `.ps1` scripts: ✅ Should continue to work
2. Routes serving static files (.css, .js, .html, etc.): ✅ Should continue to work
3. Routes using direct commands: ❌ Will return 500 error - **migration required**

Check your logs for messages like:
```
ERROR: Invoke-RequestRouter: Route command 'Get-Process' has invalid extension ''. Only .ps1 scripts and static files allowed.
```

## Questions or Issues?

If you need help migrating your routes or have questions about this security fix, please create an issue in the repository.

## References

- CWE-78: Improper Neutralization of Special Elements used in an OS Command
- OWASP: Command Injection
- PowerShell Best Practices: Avoid Invoke-Expression
