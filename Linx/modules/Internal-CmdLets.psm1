import-module 'C:\RestPS\RestPSModule\RestPSCustomModule.psm1' -force
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
function Get-MainUser {
    param ( $CurrentUser )

    [array]$MainUser = (New-Object adsisearcher([adsi]"LDAP://$($ScriptVariables.OU_User)","(&(objectCategory=User)(samaccountname=$CurrentUser))")).FindOne().Properties
    if ( ! $MainUser ) {
        [array]$MainUser = (New-Object adsisearcher([adsi]"LDAP://$($ScriptVariables.OU_Admin)","(&(objectCategory=User)(samaccountname=$CurrentUser))")).FindOne().Properties
        if ( $MainUser ) {
            $MainUser
        }
    }
    else { $MainUser }
}
function Get-ThemeOptions {
    param (
        [string]$CurrentUser,
        [string]$SelectedThemeToEdit,
        [switch]$List
    )
    
    $AvailableThemes = (Get-ChildItem (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'style\theme*')).BaseName
    if ( $CurrentUser ) {
        $CurrentTheme = (Get-ChildItem (Join-Path -Path $ScriptVariables.PersonalPath -ChildPath ('\' + $CurrentUser + '-*.css_link'))).BaseName
    }
    $SelectThemes = @()
    foreach ( $Theme in $AvailableThemes ) {
        if ( !$List ) {
            if ( $CurrentTheme -match ($Theme -replace 'theme-','') ) {
                $Selected = 'Selected'
            }
            else {
                if ( !$CurrentTheme -and $Theme -eq $ScriptVariables.Theme ) {
                    $Selected = 'selected'
                }
                else { $Selected = $null }
            }
            if ( $Theme -eq $ScriptVariables.Theme ) {
                $DefaultTheme = " ($($ScriptVariables.Text.DefaultText))"
            }
            else { $DefaultTheme = $null }
        }
        else {
            if ( $SelectedThemeToEdit -eq $null ) {
                if ( $Theme -eq $ScriptVariables.Theme ) {
                    $Selected = 'selected'
                    $DefaultTheme = " ($($ScriptVariables.Text.DefaultText))"
                }
                else {
                    $Selected = $null
                    $DefaultTheme = $null
                }
            }
            else {
                if ( $Theme -eq $ScriptVariables.Theme ) {
                    $DefaultTheme = " ($($ScriptVariables.Text.DefaultText))"
                }
                else { $DefaultTheme = $null }
                if ( $Theme -eq $SelectedThemeToEdit ) {
                    $Selected = 'selected'
                }
                else { $Selected = $null }
            }
        }
        $SelectThemes += '<option value="' + $Theme + '" ' + $Selected + '>' + ($Theme -replace '_',' ' -replace 'theme-','') + $DefaultTheme + '</option>'
    }
    $SelectThemes = $SelectThemes -join ''
    $SelectThemes
}
function ConvertFrom-CSS {
    
    [CmdletBinding(DefaultParameterSetName = 'Theme')]
    param (
        [Parameter(ParameterSetName = 'Theme')]
        [string]$Theme,
        [Parameter(ParameterSetName = 'CurrentUserTheme')]
        [string]$CurrentUserTheme
    )

    if ( $Theme ) { $UsingTheme = $Theme }
    if ( $CurrentUserTheme ) { $UsingTheme = $CurrentUserTheme }

    $PageCSS = $((Get-Content (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath ('style\' + $UsingTheme + '.css'))) -Replace "(<style>|</style>)","").trim()
    $pscustomobj = $null
    foreach ( $obj in $PageCSS ) {
        if ( $obj -match "{" -and $Parent -eq $null ) {
            $Parent = [regex]::match($obj,".*[^{]").value.trim().tolower()
            $pscustomobj += @{
                [regex]::match($obj,".*[^{]").value.trim().tolower() = @{}
            }
        }
        elseif ( $obj -match "}" -and $Parent -ne $null ) {
            $Parent = $null
        }
        elseif ( $obj -match ":.*;" -and $Parent -ne $null ) {
            try {
                $pscustomobj.$Parent += @{
                    [regex]::match($obj,".*(?=:)").value.trim() = [regex]::match($obj,"(?<=:).*[^;]").value.trim()
                }
            }
            catch {
                $pscustomobj.$Parent.Remove($([regex]::match($obj,".*(?=:)").value.trim()))
                $pscustomobj.$Parent += @{
                    [regex]::match($obj,".*(?=:)").value.trim() = [regex]::match($obj,"(?<=:).*[^;]").value.trim()
                }
            }
        }
    }
    $pscustomobj
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
#endregion