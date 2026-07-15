# Security Review – Linx 2.0

Linx 2.0 is a PowerShell-based intranet link-portal that runs on top of the RestPS listener and relies on the C# RestPSWrapper for transport-level security (authentication, CSRF, rate limiting, and security headers). The findings below are specific to the Linx application layer — the PowerShell endpoints, data handling, and access-control logic.

---

## 🔴 HIGH – Any Authenticated User Can Create or Modify Shared Links

**File:** `endpoints/Management.ps1` – `Type = 'new'` and `Type = 'update'` branches

`Management.ps1` resolves `$EditAccess` and `$AdminAccess` (lines 12–21) but never checks either flag before writing to the shared links file:

```powershell
# Type = 'new' – no $EditAccess check
$SaveString | out-file $ScriptVariables.LinksFilePath -Encoding ... -Append

# Type = 'update' – no $EditAccess check
(Get-Content "$($ScriptVariables.LinksFilePath)").replace($Find, $Replace) | Set-Content $ScriptVariables.LinksFilePath ...
```

Any user that can reach the `/ManageLink` POST endpoint (i.e., every user whose Windows account resolves in AD) can add, modify, enable/disable, or change the role/visibility of every shared link in the catalogue.

**Fix:** Wrap both the `new` (non-personal) and `update` (8-digit ID) code paths in `if ( $EditAccess -or $AdminAccess )` guards, and return a 403-equivalent response for unauthorised callers.

---

## 🔴 HIGH – LDAP Injection via Unsanitised `$CurrentUser`

**File:** `modules/Internal-CmdLets.psm1` – `Get-MainUser`

The ADSI filter is built by string interpolation from the unvalidated `$CurrentUser` value:

```powershell
(New-Object adsisearcher([adsi]"LDAP://$($ScriptVariables.OU_User)",
    "(&(objectCategory=User)(samaccountname=$CurrentUser))")).FindOne()
```

An attacker who can control the `X-Authenticated-User` header (possible if the PS backend port is directly reachable — see the RestPSWrapper review) can pass a value such as `*` or `x)(|(samaccountname=*)` to match arbitrary directory objects. Because the return value of `Get-MainUser` is used as the primary authorisation gate throughout every endpoint (`if ( !$MainUser ) { return … }`), a successful injection could allow an unauthenticated caller to impersonate any user.

**Fix:** Escape LDAP special characters in `$CurrentUser` before embedding it in the filter (replace `*`, `(`, `)`, `\`, `NUL` with their RFC 4515 escape sequences), or validate that the value matches a strict alphanumeric/domain pattern before the query.

---

## 🔴 HIGH – URL Field Stored Without Server-Side Validation (Stored XSS)

**File:** `endpoints/Management.ps1` – `URL` attribute

Every other user-supplied field (Name, Description, Category, Role, Tags, Contact, Notes) is validated against a regex pattern before being accepted. The `URL` field is stored unconditionally:

```powershell
URL { $LinkURL = $attrib.value }
```

This allows an attacker with any write access to store a `javascript:` or `data:text/html` URI. Every user who later clicks that link in `Get-Links.ps1`, `Get-LinksAdmin.ps1`, or `Get-LinksPersonal.ps1` will trigger script execution in their browser, as the URL is placed directly into an `href` attribute without encoding:

```powershell
'<a href="' + $Link.URL + '" target="_blank"/>' + $Link.Name + '</a>'
```

**Fix:** Validate `$LinkURL` against a strict allowlist of URL schemes (e.g., `^https?://`). Reject any value that does not match before writing it to the CSV.

---

## 🟡 MEDIUM – Path Traversal via `$CurrentUser` in File Paths

**Files:** `endpoints/Get-Links.ps1`, `endpoints/Get-LinksPersonal.ps1`, `endpoints/Get-LinksAdmin.ps1`, `endpoints/Management.ps1`

`$CurrentUser` is stripped of the domain prefix but is otherwise placed directly into file-system paths:

```powershell
$PersonalPath = "$($ScriptVariables.PersonalPath)\$CurrentUser.csv"
Get-ChildItem ($ScriptVariables.PersonalPath + '\' + $CurrentUser + '-*.css_link')
'' | Out-File ($ScriptVariables.PersonalPath + '\' + $CurrentUser + '.accesstime')
```

A username containing `..` (e.g., `..\..\bin\links`) would resolve to paths outside `bin\personal\`, allowing reads or writes to arbitrary files on the server — including overwriting `links.csv`, `changes.log`, or configuration files.

Although Windows authentication constrains valid `samaccountname` values in practice, the domain-strip regex `($ScriptVariables.Domain + '\\')` can be evaded if `$ScriptVariables.Domain` is empty or misconfigured.

**Fix:** After stripping the domain, validate `$CurrentUser` with a strict pattern (e.g., `^[a-zA-Z0-9\.\-_]{1,64}$`) and abort if it does not match.

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

| Severity | Issue |
|---|---|
| 🔴 HIGH | Any authenticated user can create or modify shared links (no EditAccess check) |
| 🔴 HIGH | LDAP injection via unsanitised `$CurrentUser` in ADSI filter |
| 🔴 HIGH | URL field stored without validation — stored XSS via `javascript:` URI |
| 🟡 MEDIUM | Path traversal via `$CurrentUser` in file paths |
| 🟡 MEDIUM | Open redirect via unvalidated `$Source` in theme-selection form action |
| 🟡 MEDIUM | `EditTheme` not validated — admin-level path traversal to overwrite files |
| 🟡 MEDIUM | Group membership checked with `-match` (regex) instead of exact equality |
| 🟠 LOW | Log injection via unsanitised `$CurrentUser` and `$LinkName` |
| 🟠 LOW | Hardcoded absolute module path in `Internal-CmdLets.psm1` |
| 🟠 LOW | Link field values inserted into HTML without entity encoding |
