# Security Review – Linx 2.0 (Re-evaluated)

This report re-evaluates the previous findings against the current codebase.

---

## ✅ Resolved Since Previous Review

- Shared-link create/update now requires `EditAccess` or `AdminAccess` in `endpoints/Management.ps1`.
- `CurrentUser` is now validated with `^[a-zA-Z0-9\.\-_]{1,64}$` in endpoint entry points before LDAP/file-path usage.
- URL input in `Management.ps1` now enforces absolute `http/https` URLs.
- The old `SelectTheme` open-redirect source parameter flow is no longer present.
- Previous `EditTheme` path-traversal flow is no longer present.
- Edit/admin group checks no longer rely on simple `-match` string matching.

---

## 🟡 MEDIUM – Role Matching Still Uses Regex (`-match`) Instead of Exact Membership

**File:** `endpoints/Get-Links.ps1` (role gate when rendering links)

Role-based visibility still uses:

```powershell
if ( $MainUser.memberof -match "$Role" )
```

This is regex/substring matching, not exact DN/group equality, and can over-match similarly named groups.

**Recommendation:** Compare role values to exact group identifiers (`-in`/exact equality) or use escaped, anchored matching.

---

## 🟠 LOW – `Get-MainUser` LDAP Filter Still Uses Raw Interpolation (Fragile Hardening)

**File:** `modules/Internal-CmdLets.psm1` (`Get-MainUser`)

Current endpoint validation makes practical exploitation much harder, but `Get-MainUser` still builds LDAP filters with direct interpolation.

**Recommendation:** Escape LDAP filter input in `Get-MainUser` as defense-in-depth so safety does not depend on all callers validating first.

---

## 🟠 LOW – Log Injection Risk from Unescaped Link Names

**Files:** `endpoints/Management.ps1`, `endpoints/Get-LinksAdmin.ps1`

Log messages include user-controlled link names directly. Newline/control-character normalization is still not enforced before `Write-Log` calls.

**Recommendation:** Strip `\r`/`\n` and other control characters before writing user-derived values to logs.

---

## 🟠 LOW – Hardcoded Absolute Module Import Path

**File:** `modules/Internal-CmdLets.psm1` (line 1)

```powershell
import-module 'C:\RestPS\RestPSModule\RestPSCustomModule.psm1' -force
```

This remains environment-specific and brittle.

**Recommendation:** Resolve module path from `$ScriptVariables.ScriptPath` with `Join-Path`.

---

## Summary Table

| Severity | Issue |
|---|---|
| 🟡 MEDIUM | Role matching uses regex/substring logic (`-match`) |
| 🟠 LOW | LDAP filter interpolation in `Get-MainUser` remains fragile hardening-wise |
| 🟠 LOW | Log injection risk from unescaped user-derived values |
| 🟠 LOW | Hardcoded absolute module import path |
