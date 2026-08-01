function Get-HTMLHead {
param ( $CSS )
@"
<html lang="{{PSVar_htmlLanguage}}">
<head>
  <meta charset='{{PSVar_HTMLCharset}}'>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="description" content="{{PSVar_pageDescription}}">
  <title>{{PSVar_pageTitle}}</title>
  <link rel="shortcut icon" href="/favicon.ico" />
</head>
$CSS
<body>
  $(if ( $ScriptVariables.Logo ) { '<br><br><img id="logo" width="' + $ScriptVariables.LogoWidth + '" src="data:image/png;base64, ' + $ScriptVariables.Logo + '"/>' })<br>
  <h2>$($ScriptVariables.Text.Title)</h2>
"@
}

<#
.SYNOPSIS
    Validates HMAC-SHA256 request signature from RestPSWrapper
.DESCRIPTION
    Validates the X-Request-Signature header sent by the .NET wrapper.
    The signature is HMAC-SHA256 of: {user}|{method}|{path}|{bodyLength}|{body}
    Uses constant-time comparison to prevent timing attacks.
.PARAMETER Request
    The HttpListenerRequest object from the PowerShell backend
.PARAMETER Body
    The request body content (use "[EMPTY]" if body is null/empty)
.PARAMETER Secret
    The shared secret from base_settings.json RequestSignatureSecret
.EXAMPLE
    $isValid = Test-RequestSignature -Request $script:Request -Body $script:Body -Secret $ScriptVariables.RequestSignatureSecret
    if (-not $isValid) {
        $script:StatusCode = 401
        $script:StatusDescription = "Unauthorized - Invalid Signature"
        return $null
    }
.NOTES
    This function requires .NET classes for HMAC-SHA256 computation.
    Returns $true if signature is valid, $false otherwise.
#>
function Test-RequestSignature {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Body,

        [Parameter(Mandatory = $true)]
        [string]$Secret
    )

    try {
        # Extract signature from header
        $providedSignature = $Request.Headers["X-Request-Signature"]
        if ([string]::IsNullOrEmpty($providedSignature)) {
            Write-Warning "Test-RequestSignature: No X-Request-Signature header found"
            return $false
        }

        # Extract user from header (sent by wrapper)
        $userName = $Request.Headers["X-Authenticated-User"]
        if ([string]::IsNullOrEmpty($userName)) {
            $userName = "Unknown"
        }

        # Get request details
        $method = $Request.HttpMethod
        $path = $Request.Url.AbsolutePath

        # Build signature data matching wrapper logic
        # Wrapper uses: {userName}|{method}|{path}|{bodyLength}|{body or "[EMPTY]"}
        $bodyForSignature = if ([string]::IsNullOrEmpty($Body)) { "[EMPTY]" } else { $Body }
        $bodyLength = if ([string]::IsNullOrEmpty($Body)) { 0 } else { $Body.Length }
        $signatureData = "$userName|$method|$path|$bodyLength|$bodyForSignature"

        # Compute HMAC-SHA256
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Secret)
        $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($signatureData))
        $expectedSignature = [Convert]::ToBase64String($hashBytes)
        $hmac.Dispose()

        # Constant-time comparison to prevent timing attacks
        # Convert both signatures to byte arrays and compare
        try {
            $expectedBytes = [Convert]::FromBase64String($expectedSignature)
            $providedBytes = [Convert]::FromBase64String($providedSignature)

            if ($expectedBytes.Length -ne $providedBytes.Length) {
                Write-Warning "Test-RequestSignature: Signature length mismatch"
                return $false
            }

            # XOR all bytes - if any differ, result will be non-zero
            $result = 0
            for ($i = 0; $i -lt $expectedBytes.Length; $i++) {
                $result = $result -bor ($expectedBytes[$i] -bxor $providedBytes[$i])
            }

            $isValid = ($result -eq 0)

            if (-not $isValid) {
                Write-Warning "Test-RequestSignature: Signature mismatch for $method $path user=$userName"
            }

            return $isValid
        }
        catch {
            Write-Warning "Test-RequestSignature: Error comparing signatures: $_"
            return $false
        }
    }
    catch {
        Write-Error "Test-RequestSignature: Error validating signature: $_"
        return $false
    }
}

function Get-MainUser {
    param ( $CurrentUser )
    [array]$MainUser = (New-Object adsisearcher([adsi]"LDAP://$($ScriptVariables.OU_User)","(&(objectCategory=User)(samaccountname=$CurrentUser))")).FindOne().Properties
    if ( ! $MainUser ) {
        [array]$MainUser = (New-Object adsisearcher([adsi]"LDAP://$($ScriptVariables.OU_Admin)","(&(objectCategory=User)(samaccountname=$CurrentUser))")).FindOne().Properties
        if ( $MainUser ) { $MainUser }
    }
    else { $MainUser }
}
function Get-ThemeOptions {
    param ( [string]$CurrentUser )    
    if ( $CurrentUser ) { $CurrentTheme = (Get-ChildItem (Join-Path -Path $ScriptVariables.PersonalPath -ChildPath "$($CurrentUser)-*.css_link")).BaseName }
    $SelectThemes = @()
    foreach ( $Theme in $AvailableThemes ) {
        if ( $CurrentTheme -match ($Theme -replace 'theme-','') ) { $Selected = 'Selected' }
        else {
            if ( !$CurrentTheme -and $Theme -eq $ScriptVariables.Theme ) { $Selected = 'selected' }
            else { $Selected = $null }
        }
        if ( $Theme -eq $ScriptVariables.Theme ) { $DefaultTheme = " ($($ScriptVariables.Text.DefaultText))" }
        else { $DefaultTheme = $null }
        $SelectThemes += '<option value="' + $Theme + '" ' + $Selected + '>' + ($Theme -replace '_',' ' -replace 'theme-','') + $DefaultTheme + '</option>'
    }
    $SelectThemes = $SelectThemes -join ''
    $SelectThemes
}
#region declare variables
    $global:ScriptVariables += @{ 
        LinksFilePath    = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'bin\links.csv'
        RemovedLinksPath = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'bin\removed_links.csv'
        PersonalPath     = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'bin\personal'
        LogChangesPath   = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'logs\changes.log'
        LogRestPSPath    = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'logs\RestPS.log'
        SettingsPath     = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'settings\'
        RegExpsPath      = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'settings\regexps.json'
        LanguagePath     = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'lang\'
        Logo             = Get-Content (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'images\logo_base64.txt')
    }
    (Get-Content (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'base_settings.json') | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables[$_.Name] = $_.Value }
    (Get-Content (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'settings\custom_settings.json') | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables[$_.Name] = $_.Value }
    $ScriptVariables.CSSpath = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath ('style\' + $ScriptVariables.Theme + '.css')
    $ScriptVariables.Text = $ScriptVariables.Text = @{} ; (Get-Content (Join-Path -Path $ScriptVariables.LanguagePath -ChildPath ($ScriptVariables.Language + '.json')) | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables.Text[$_.Name] = $_.Value } | Sort Name
    $ScriptVariables.Regex = $ScriptVariables.Regex = @{} ; (Get-Content $ScriptVariables.RegExpsPath | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables.Regex[$_.Name] = $_.Value } | Sort Name
    $global:Logfile = $ScriptVariables.LogChangesPath
    [array]$Global:EditMembers = (New-Object adsisearcher([adsi]"LDAP://$($ScriptVariables.OU_Group)","(name=$($ScriptVariables.EditGroup))")).FindOne().Properties.member
    [array]$Global:AdminMembers = (New-Object adsisearcher([adsi]"LDAP://$($ScriptVariables.OU_Group)","(name=$($ScriptVariables.AdminGroup))")).FindOne().Properties.member

    $global:Links = Import-CSV $ScriptVariables.LinksFilePath -Delimiter $ScriptVariables.CSVDelimiter
    $global:AvailableThemes = (Get-ChildItem (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'style\theme*')).BaseName
#endregion