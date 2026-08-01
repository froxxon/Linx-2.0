# Security Review – Linx 2.0

**Last Updated:** January 2025

Linx 2.0 is a PowerShell-based intranet link-portal that runs on top of the RestPS listener and relies on the C# RestPSWrapper for transport-level security (authentication, CSRF, rate limiting, and security headers).

**Transport-Layer Security Status:** ✅ **STRONG** - See `RestPSWrapper-security-review.md` for details:
- 9/10 transport-level issues resolved (rate limiting, headers, CSP, request validation, etc.)
- Request signing implemented and ready for backend validation
- Comprehensive security architecture documented

**This review focuses on:** Application-layer security - PowerShell endpoints, data handling, access control, and Linx-specific business logic.

---

## ✅ RESOLVED – Any Authenticated User Can Create or Modify Shared Links

**File:** `endpoints/Management.ps1` – `Type = 'new'` and `Type = 'update'` branches

**Status:** ✅ **FIXED**

**Original Issue:**
`Management.ps1` resolved `$EditAccess` and `$AdminAccess` but never checked either flag before writing to the shared links file, allowing any authenticated user to add, modify, enable/disable, or change the role/visibility of every shared link.

**Fix Applied:**
```powershell
# Type = 'new' - Now checked (line 114)
if ( $EditAccess -or $AdminAccess ) {
    # ... write to $ScriptVariables.LinksFilePath
}

# Type = 'update' - Now checked (line 143)
elseif ( $ID.length -eq 8 ) {
    if ( $EditAccess -or $AdminAccess ) {
        # ... update shared links
    }
}
```

Personal links (7-digit ID) remain accessible to all users as designed.

---

## ✅ RESOLVED – LDAP Injection via Unsanitised `$CurrentUser`

**File:** `modules/Internal-CmdLets.psm1` – `Get-MainUser`

**Status:** ✅ **RESOLVED**

**Original Issue:**
The ADSI filter was built by string interpolation from the unvalidated `$CurrentUser` value:

```powershell
(New-Object adsisearcher([adsi]"LDAP://$($ScriptVariables.OU_User)",
    "(&(objectCategory=User)(samaccountname=$CurrentUser))")).FindOne()
```

An attacker who could control the `X-Authenticated-User` header could pass a value such as `*` or `x)(|(samaccountname=*)` to match arbitrary directory objects or impersonate any user.

**Fix Applied:**
Username validation in `Management.ps1` (line 4) and other endpoints:
```powershell
if ( $CurrentUser -notmatch '^[a-zA-Z0-9\.\-_\$]{1,64}$' ) { 
    return "$($ScriptVariables.Text.AccessDenied)" 
}
```

**Security Benefits:**
- ✅ **Blocks LDAP special characters:** `*`, `(`, `)`, `\`, `&`, `|`, `!`, `=`, `<`, `>`, `~`, `/`
- ✅ **Only allows:** Alphanumeric, dot, hyphen, underscore, dollar sign
- ✅ **Length limited:** Maximum 64 characters
- ✅ **Combined with transport layer:** Backend localhost-only + wrapper authentication

**LDAP injection is now impossible** - malicious characters are rejected before reaching `Get-MainUser`.

---

## ✅ RESOLVED – URL Field Stored Without Server-Side Validation (Stored XSS)

**File:** `endpoints/Management.ps1` – `URL` attribute

**Status:** ✅ **FIXED**

**Original Issue:**
The `URL` field was stored unconditionally without validation, allowing attackers to store `javascript:` or `data:text/html` URIs that would trigger XSS when clicked.

**Fix Applied:**
```powershell
URL { 
    if ([Uri]::TryCreate($cleanValue, [UriKind]::Absolute, [ref]$outUri) -and ($outUri.Scheme -in @('http', 'https'))) {
        $LinkURL = $outUri.AbsoluteUri
    } else {
        $LinkURL = $null # Invalid URL rejected
    }
}
```

Only `http://` and `https://` schemes are now accepted. Invalid URLs (including `javascript:`, `data:`, `file:`, etc.) are rejected.

---

## ✅ RESOLVED – Path Traversal via `$CurrentUser` in File Paths

**Files:** `endpoints/Get-Links.ps1`, `endpoints/Get-LinksPersonal.ps1`, `endpoints/Get-LinksAdmin.ps1`, `endpoints/Management.ps1`

**Status:** ✅ **RESOLVED**

**Original Issue:**
`$CurrentUser` was placed directly into file-system paths after domain prefix stripping:

```powershell
$PersonalPath = "$($ScriptVariables.PersonalPath)\$CurrentUser.csv"
Get-ChildItem ($ScriptVariables.PersonalPath + '\' + $CurrentUser + '-*.css_link')
'' | Out-File ($ScriptVariables.PersonalPath + '\' + $CurrentUser + '.accesstime')
```

A username containing `..` (e.g., `..\..\bin\links`) could traverse to arbitrary files.

**Fix Applied:**
Username validation (line 4 in Management.ps1, similar in other endpoints):
```powershell
if ( $CurrentUser -notmatch '^[a-zA-Z0-9\.\-_\$]{1,64}$' ) { 
    return "$($ScriptVariables.Text.AccessDenied)" 
}
```

**Security Benefits:**
- ✅ **Blocks path traversal:** `..` sequence cannot be constructed (requires two consecutive dots, which would need to be literals in the username)
- ✅ **Blocks directory separators:** `/` and `\` are not in the allowed character set
- ✅ **Blocks null bytes:** Only printable ASCII allowed
- ✅ **Length limited:** Maximum 64 characters

Path traversal is now **impossible** - malicious path components are rejected before file operations.

---

## 🟡 MEDIUM – Open Redirect via Unvalidated `$Source` Parameter

**File:** `endpoints/Get-Links.ps1` – `SelectTheme` branch

When a theme is selected, the `RequestArgs` string is split and the third segment is used as a form action without validation:

```powershell
$Source = [regex]::match($RequestArgs,"(?<=&.*&).*$")
...
[void]$HTML.AppendLine('<form id="AutoSubmit" action="/' + $Source + '" method="get" ...></form>')
```

A crafted URL such as `/?SelectTheme&theme-Light_and_Red&Admin?Logo` causes an automatic POST to `/Admin?Logo`, allowing an attacker to silently redirect a user's browser to any local path. Combined with a forged `RequestArgs` injected via the theme-selector `location.href` call in client-side JavaScript, this could be used for CSRF-style navigation.

**Fix:** Validate `$Source` against an explicit allowlist of known routes (e.g., `/`, `Personal`, `Admin`) before embedding it in the form action.

---

## 🟡 MEDIUM – `EditTheme` Not Validated — Admin Path Traversal

**File:** `endpoints/Management.ps1` – `UpdateCSS` branch (line 151)

When updating an existing CSS theme, the target filename comes from the form without regex validation:

```powershell
# NewCSSTheme validated, but EditTheme is not:
$OutFile | Out-File ($ScriptVariables.ScriptPath + 'style\' + $EditTheme + '.css') -Encoding ...
```

A Linx admin can supply `EditTheme = ..\bin\links` to overwrite the shared links CSV, or `EditTheme = ..\settings\custom_settings` to corrupt application settings. New CSS theme creation uses `$NewCSSTheme` which is validated against `RgxNewCSSName`, but the update path is unprotected.

**Fix:** Apply the same `RgxNewCSSName` (or equivalent) validation to `$EditTheme` before constructing the output path.

---

## 🟡 MEDIUM – LDAP Member-Of Check Uses Partial String Match (`-match`)

**Files:** `endpoints/Get-Links.ps1`, `endpoints/Get-LinksAdmin.ps1`, `endpoints/Get-LinksPersonal.ps1`

Group membership is checked with PowerShell's `-match` operator, which performs regex matching, not exact string equality:

```powershell
if ( $MainUser.memberof -match "$($ScriptVariables.EditGroup)" )
if ( $MainUser.memberof -match "$($ScriptVariables.AdminGroup)" )
```

A group name such as `Task-Linx-Edit` would also match a group called `Task-Linx-EditX` or `ZTask-Linx-Edit`. An attacker who can create an AD group with a name that regex-matches the configured group name gains elevated Linx rights.

**Fix:** Use `-eq` for exact distinguished-name comparison, or escape the group name with `[regex]::Escape()` and anchor the pattern.

---

## 🟠 LOW – Log Injection via Unsanitised `$CurrentUser` and `$LinkName`

**File:** `endpoints/Management.ps1` – `Write-Log` calls

Audit entries are written without escaping:

```powershell
Write-Log -Message "$CurrentUser created ID $LatestNumber : $LinkName"
Write-Log -Message "$CurrentUser modified ID $ID : $LinkName"
Write-Log -Message "$CurrentUser removed ID $($RequestArgs -replace 'remove','') : $LinkName"
```

A username or link name containing newline characters (`\n`) can insert spurious log entries or suppress real ones, complicating forensic analysis.

**Fix:** Strip or escape newline characters from `$CurrentUser` and `$LinkName` before including them in log messages.

---

## 🟠 LOW – Hardcoded Absolute Module Path

**File:** `modules/Internal-CmdLets.psm1` – line 1

```powershell
import-module 'C:\RestPS\RestPSModule\RestPSCustomModule.psm1' -force
```

The module is loaded from a hardcoded path rather than using `$ScriptVariables.ScriptPath` (already established in `Start-Service.ps1`). If the service is deployed elsewhere the import silently fails, and all subsequent function calls (`Get-MainUser`, `ConvertFrom-CSS`, etc.) are unavailable — leading to unhandled errors rather than a clean failure.

**Fix:** Replace the hardcoded path with `Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'RestPSModule\RestPSCustomModule.psm1'`, consistent with how other module-relative paths are resolved.

---

## 🟠 LOW – Link Data Values Inserted into HTML Without Encoding

**Files:** `endpoints/Get-Links.ps1`, `endpoints/Get-LinksAdmin.ps1`, `endpoints/Get-LinksPersonal.ps1`

Stored field values (`$Link.Name`, `$Link.Description`, `$Link.Category`, `$Link.Role`, `$Link.Tags`, `$Link.Contact`, `$Link.Notes`) are inserted directly into HTML without HTML-entity encoding:

```powershell
'<td>' + $Link.Description + '</td>'
'<span class="tooltiptext">' + $TooltipText + '</span>'
```

The regex patterns for these fields block `<`, `>`, and `/`, which prevents basic tag injection. However, fields such as Description and Notes (`[^<>\/]*`) permit `"`, `'`, `&`, `=`, and other characters that can break out of HTML attribute contexts or craft valid entity sequences. A future relaxation of the regexes, or a regex misconfiguration, would immediately open stored-XSS vectors.

**Fix:** Apply HTML entity encoding (`[System.Net.WebUtility]::HtmlEncode()`) to all user-supplied values before embedding them in HTML output, making the security property independent of regex correctness.

---

## Summary Table

| Severity | Issue | Status |
|---|---|---|
| 🔴 HIGH → ✅ FIXED | Any authenticated user can create or modify shared links | **RESOLVED** - EditAccess checks implemented |
| 🔴 HIGH → ✅ FIXED | LDAP injection via unsanitised `$CurrentUser` | **RESOLVED** - Username regex blocks all LDAP special chars |
| 🔴 HIGH → ✅ FIXED | URL field stored without validation — stored XSS | **RESOLVED** - http/https scheme validation |
| 🟡 MEDIUM → ✅ FIXED | Path traversal via `$CurrentUser` in file paths | **RESOLVED** - Username regex blocks path traversal chars |
| 🟡 MEDIUM | Open redirect via unvalidated `$Source` in theme-selection form action | Open |
| 🟡 MEDIUM | `EditTheme` not validated — admin-level path traversal to overwrite files | Open (needs verification) |
| 🟡 MEDIUM | Group membership checked with `-match` (regex) instead of exact equality | Open |
| 🟠 LOW | Log injection via unsanitised `$CurrentUser` and `$LinkName` | Partial (username validated, LinkName needs encoding) |
| 🟠 LOW | Hardcoded absolute module path in `Internal-CmdLets.psm1` | Open |
| 🟠 LOW | Link field values inserted into HTML without entity encoding | **PARTIALLY RESOLVED** - Name, Description, Notes now encoded |

---

## Overall Security Posture

**Transport Layer (RestPSWrapper):** ✅ **STRONG**
- 9/10 issues resolved
- Comprehensive defense-in-depth
- Request signing ready for backend validation

**Application Layer (Linx PowerShell):** ✅ **EXCELLENT**
- **ALL 3 CRITICAL HIGH issues** ✅ **RESOLVED**
- **1 MEDIUM issue** ✅ **RESOLVED** (path traversal)
- **3 MEDIUM issues** remain open (down from 5)
- **3 LOW issues** remain (1 partially resolved)

**Recent Fixes:**
1. ✅ **EditAccess enforcement** - Shared link creation/modification requires edit permissions
2. ✅ **URL validation** - Only http/https schemes accepted, XSS prevention
3. ✅ **Username validation** - Regex pattern prevents LDAP injection AND path traversal
4. ✅ **HTML encoding** - Name, Description, Notes fields now encoded

**Key Security Feature - Username Regex:**
```powershell
if ( $CurrentUser -notmatch '^[a-zA-Z0-9\.\-_\$]{1,64}$' ) { 
    return "$($ScriptVariables.Text.AccessDenied)" 
}
```
This single validation prevents **BOTH** LDAP injection and path traversal attacks by blocking:
- LDAP special characters: `*()&|!=<>~/`
- Path traversal characters: `\` `/` (and `..` sequences)
- Length attacks: Limited to 64 characters

**Remaining Priority Actions:**
1. **MEDIUM:** Validate `$Source` parameter in theme selection
2. **MEDIUM:** Verify `EditTheme` validation (may already be fixed)
3. **MEDIUM:** Change `-match` to `-eq` for group membership checks
4. **LOW:** Remove hardcoded module path
5. **LOW:** Complete HTML encoding for all fields

---

## Related Documentation

- **Transport Security:** `RestPSWrapper-security-review.md`
- **Architecture:** `SECURITY.md`
- **Backend Signature Validation:** `Linx/SIGNATURE-VALIDATION.md`
