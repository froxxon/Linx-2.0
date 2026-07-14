param( $Body, $RequestArgs )

$CurrentUser = $null
$CurrentUser = $($Request.Headers['X-Authenticated-User'] -replace ("$($ScriptVariables.Domain)\\",''))  
$MainUser = Get-MainUser $CurrentUser
if ( !$MainUser ) {
    return 'An unspecified error has occured'
}

$EditAccess = $null
$AdminAccess = $null
foreach ( $group in $EditMembers ) {
    if ( $group -in $MainUser.memberof -or $group -eq $MainUser.distinguishedname ) {
        $EditAccess = $true
    }
}
foreach ( $group in $AdminMembers ) {
    if ( $group -in $MainUser.memberof -or $group -eq $MainUser.distinguishedname ) {
        $AdminAccess = $true
    }
}

$Output = @"
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Type" content="multipart/form-data;charset=$($ScriptVariables.Charset)">
</head>
<body>
"@
$Attributes = $(([regex]::matches($Body,"(?s)(?<=name=`").*?(?=---)")) | Select-Object -ExpandProperty Value)
$RequestObj = @{}
foreach ( $obj in $Attributes ) {
    $Name, $Value = $obj.split('"')
    $RequestObj.Add($Name,$Value.Trim())
}

<#
foreach ( $attrib in $RequestObj.GetEnumerator() ) {
    switch ($attrib.name) {
        Name { if ( $attrib.value -match $ScriptVariables.Regex.RgxName ) { $LinkName = $attrib.value } }
        URL { $LinkURL = $attrib.value }
        Description { if ( $attrib.value -match $ScriptVariables.Regex.RgxDescription ) { $LinkDescription = $attrib.value } }
        Category { if ( $attrib.value -match $ScriptVariables.Regex.RgxCategory ) { $LinkCategory = $attrib.value } }
        Role { if ( $attrib.value -match $ScriptVariables.Regex.RgxRole ) { $LinkRole = $attrib.value } }
        Enabled { $LinkEnabled = $attrib.value }
        Personal { $LinkPersonal = $attrib.value }
        Type { $Type = $attrib.value }
        Contact { if ( $attrib.value -match $ScriptVariables.Regex.RgxContact ) { $LinkContact = $attrib.value } }
        Notes { if ( $attrib.value -match $ScriptVariables.Regex.RgxNotes ) { $LinkNotes = $attrib.value } }
        Tags { if ( $attrib.value -match $ScriptVariables.Regex.RgxTags ) { $LinkTag = $attrib.value } }
        ID { $ID = $attrib.value }
        Logo { $Logo = $attrib.value }
        Language { $Language = $attrib.value }
        LogoWidth { $LogoWidth = $attrib.value }
        LogRows { $LogRows = $attrib.value }
        Theme { $Theme = $attrib.value }
        EditTheme { $EditTheme = $attrib.value }
        AllowPersonalLinks { $AllowPersonalLinks = $attrib.value }
        AllowPersonalTheme { $AllowPersonalTheme = $attrib.value }
        ShowFooter { $ShowFooter = $attrib.value }
        NewCSSTheme { if ( $attrib.value -match $ScriptVariables.Regex.RgxNewCSSName ) { $NewCSSTheme = $attrib.value.trim() -replace ' ','_' } }
    }
}
#>
foreach ( $attrib in $RequestObj.GetEnumerator() ) {
    $cleanValue = $attrib.value.ToString().Trim()
    $outUri = $null

    switch ($attrib.name) {
        Name { 
            if ( $cleanValue -match $ScriptVariables.Regex.RgxName ) { 
                $LinkName = [System.Net.WebUtility]::HtmlEncode($cleanValue) 
            } 
        }
        URL { 
            if ([Uri]::TryCreate($cleanValue, [UriKind]::Absolute, [ref]$outUri) -and ($outUri.Scheme -in @('http', 'https'))) {
                $LinkURL = $outUri.AbsoluteUri
            } else {
                $LinkURL = $null # Or handle invalid URL error
            }
        }
        Description { 
            if ( $cleanValue -match $ScriptVariables.Regex.RgxDescription ) { 
                $LinkDescription = [System.Net.WebUtility]::HtmlEncode($cleanValue) 
            } 
        }
        Category { if ( $cleanValue -match $ScriptVariables.Regex.RgxCategory ) { $LinkCategory = $cleanValue } }
        Role     { if ( $cleanValue -match $ScriptVariables.Regex.RgxRole ) { $LinkRole = $cleanValue } }
        
        Enabled { $LinkEnabled = $attrib.value }
        Personal { $LinkPersonal = $attrib.value }

        Type     { $Type = [System.Net.WebUtility]::HtmlEncode($cleanValue) }
        Contact  { if ( $cleanValue -match $ScriptVariables.Regex.RgxContact ) { $LinkContact = $cleanValue } }
        Notes    { 
            if ( $cleanValue -match $ScriptVariables.Regex.RgxNotes ) { 
                $LinkNotes = [System.Net.WebUtility]::HtmlEncode($cleanValue) 
            } 
        }
        Tags     { if ( $cleanValue -match $ScriptVariables.Regex.RgxTags ) { $LinkTag = $cleanValue } }
        
        ID       { if ($cleanValue -match '^\d+$') { $ID = [int]$cleanValue } }
        
        Logo { 
            if ([Uri]::TryCreate($cleanValue, [UriKind]::Absolute, [ref]$outUri) -and ($outUri.Scheme -in @('http', 'https'))) {
                $Logo = $outUri.AbsoluteUri
            }
        }
        Language { if ($cleanValue -match '^[a-zA-Z\-]{2,5}$') { $Language = $cleanValue } } # e.g., en-US
        
        LogoWidth { if ($cleanValue -match '^\d+$') { $LogoWidth = [int]$cleanValue } }
        LogRows   { if ($cleanValue -match '^\d+$') { $LogRows = [int]$cleanValue } }
        
        Theme              { if ($cleanValue -match '^[a-zA-Z0-9_\-]+$') { $Theme = $cleanValue } }
        EditTheme          { if ($cleanValue -match '^[a-zA-Z0-9_\-]+$') { $EditTheme = $cleanValue } }
        AllowPersonalLinks { $AllowPersonalLinks = $attrib.value }
        AllowPersonalTheme { $AllowPersonalTheme = $attrib.value }
        ShowFooter         { $ShowFooter = $attrib.value }
    }
}
if ( ! $LinkEnabled ) { $LinkDisabled = "true" }

if ( $Type -eq 'new' ) {
    if ( $LinkPersonal ) {
        $PersonalPath = "$($ScriptVariables.PersonalPath)\$CurrentUser.csv"
        if ( !(Test-Path $PersonalPath) ) {
            $ScriptVariables.CSVHeader | out-file $PersonalPath -Encoding $($ScriptVariables.Charset -replace '-','')
            $LatestNumber = "0000000"
        }
        else {
            $LatestNumber = $((Get-Content -Tail 1 $PersonalPath).Split(';'))[0]
            if ( $LatestNumber -eq 'ID' ) { $LatestNumber = '0000000' }
        }
        $LatestNumber = '{0:d7}' -f ([int]$LatestNumber + 1)
        $SaveString = "$LatestNumber;$LinkName;$LinkURL;$LinkDescription;$LinkCategory;$LinkRole;$LinkTag;$LinkContact;$LinkNotes;$LinkDisabled;"
        $SaveString | out-file $PersonalPath -Encoding $($ScriptVariables.Charset -replace '-','') -Append
        $Output += '<form id="AutoSubmit" action="/" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>"'
    }
    else {
        if ( !(Test-Path $ScriptVariables.LinksFilePath) ) {
            $ScriptVariables.CSVHeader | out-file $ScriptVariables.LinksFilePath -Encoding $($ScriptVariables.Charset -replace '-','')
            $LatestNumber = "00000000"
        }
        else {
            $LatestNumber = $((Get-Content -Tail 1 $ScriptVariables.LinksFilePath).Split(';'))[0]
            if ( $LatestNumber -eq 'ID' ) { $LatestNumber = '00000000' }
        }
        $LatestNumber = '{0:d8}' -f ([int]$LatestNumber + 1)
        $SaveString = "$LatestNumber;$LinkName;$LinkURL;$LinkDescription;$LinkCategory;$LinkRole;$LinkTag;$LinkContact;$LinkNotes;$LinkDisabled;"
        $SaveString | out-file $ScriptVariables.LinksFilePath -Encoding $($ScriptVariables.Charset -replace '-','') -Append
        Write-Log -Message "$CurrentUser created ID $LatestNumber : $LinkName"
        $Output += '<form id="AutoSubmit" action="/" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>"'
    }
}
elseif ( $Type -eq 'update' ) {
    if ( $ID.length -eq 7 ) {
        $PersonalPath = "$($ScriptVariables.PersonalPath)\$CurrentUser.csv"
        $Find = Select-String -Path $PersonalPath -Pattern $ID -Encoding $($ScriptVariables.Charset -replace '-','') | select-object -ExpandProperty Line
        $Replace = "$ID;$LinkName;$LinkURL;$LinkDescription;$LinkCategory;;$LinkTag;;$LinkNotes;;"
        (Get-Content $PersonalPath).replace($Find, $Replace) | Set-Content $PersonalPath  -Encoding $($ScriptVariables.Charset -replace '-','')
        $Output += '<form id="AutoSubmit" action="/Personal" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>"'
    }
    elseif ( $ID.length -eq 8 ) {
        $Find = Select-String -Path $ScriptVariables.LinksFilePath -Pattern $ID -Encoding $($ScriptVariables.Charset -replace '-','') | select-object -ExpandProperty Line
        $Replace = "$ID;$LinkName;$LinkURL;$LinkDescription;$LinkCategory;$LinkRole;$LinkTag;$LinkContact;$LinkNotes;$LinkDisabled;"
        (Get-Content "$($ScriptVariables.LinksFilePath)").replace($Find, $Replace) | Set-Content $ScriptVariables.LinksFilePath -Encoding $($ScriptVariables.Charset -replace '-','')
        Write-Log -Message "$CurrentUser modified ID $ID : $LinkName"
        $Output += '<form id="AutoSubmit" action="/Admin" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>"'
    }
}
elseif ( $RequestArgs -match '^UpdateCSS$' ) {
    if ( $AdminAccess ) {
        $OutFile = "<style>"
        $Parent = $null
        $FirstObj = $true
        $RequestObj.GetEnumerator() | Sort Name | ForEach-Object {
            $Element = ([regex]::match($_.Key,".*(?=_____)")).value
            if ( $Element -ne '' ) {
                if ( $Element -ne $Parent ) {
                    $Parent = $Element
                    $ParentCreated = $false
                    if ( !$FirstObj ) {
                        $OutFile += "  }`n"
                    }
                    else { $FirstObj = $null }
                }
                $attribute = ([regex]::match($_.Key,"(?<=_____).*")).value
                if ( $ParentCreated -eq $false ) {
                    $OutFile += "`n  $Parent {`n"
                    $OutFile += "    $($attribute ): $($_.value);`n"
                    $ParentCreated = $true
                }
                else {
                    if ( $parent -match "slider:before" -and $attribute -match 'content' -and ($_.value -eq $null -or $_.value -eq '')) {
                        $Value = '""'
                    }
                    else { $Value = $_.Value }
                    $OutFile += "    $($attribute ): $Value;`n"
                }
            }
        }
        $OutFile += "  }`n"
        $OutFile += "</style>"
        if ( $NewCSSTheme ) {
            $OutFile | Out-File ($ScriptVariables.ScriptPath + 'style\theme-' + $NewCSSTheme + '.css' ) -Encoding ($ScriptVariables.Charset -replace '-','')
        }
        else {
            $OutFile | Out-File ($ScriptVariables.ScriptPath + 'style\' + $EditTheme + '.css' ) -Encoding ($ScriptVariables.Charset -replace '-','')
        }
        $Output += '<form id="AutoSubmit" action="/Admin?CSS" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>'
    }
}
elseif ( $RequestArgs -match '^UpdateText$' ) {
    if ( $AdminAccess ) {
        $PSObject = New-Object -TypeName PSObject
        $RequestObj.GetEnumerator() | Sort Name | foreach { $PSObject | Add-Member -NotePropertyName $_.key -NotePropertyValue $_.value }
        $PSObject | ConvertTo-Json | Out-File ($ScriptVariables.LanguagePath + $ScriptVariables.Language + '.json') -Encoding ($ScriptVariables.Charset -replace '-','')
        $ScriptVariables.Text = $ScriptVariables.Text = @{} ; (Get-Content ($ScriptVariables.LanguagePath + $ScriptVariables.Language + '.json') | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables.Text[$_.Name] = $_.Value } | Sort Name
        $Output += '<form id="AutoSubmit" action="/Admin?Text" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>'
    }
}
elseif ( $RequestArgs -match '^ResetText$' ) {
    if ( $AdminAccess ) {
        $Language = ([regex]::match(($ScriptVariables.LanguagePath + $ScriptVariables.Language + '.json'),"[a-z]{2}-[a-z]{2}")).Value
        Copy-Item -Path "$(($ScriptVariables.LanguagePath + $ScriptVariables.Language + '.json') -replace "$Language","$($Language)_default")" -Destination $ScriptVariables.LanguagePath -Force
        $ScriptVariables.Text = $ScriptVariables.Text = @{} ; (Get-Content ($ScriptVariables.LanguagePath + $ScriptVariables.Language + '.json') | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables.Text[$_.Name] = $_.Value } | Sort Name
        $Output += '<form id="AutoSubmit" action="/Admin?Text" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>'
    }
}
elseif ( $RequestArgs -match '^UpdateRegex$' ) {
    if ( $AdminAccess ) {
        $PSObject = New-Object -TypeName PSObject
        $RequestObj.GetEnumerator() | Sort Name | foreach { $PSObject | Add-Member -NotePropertyName $_.key -NotePropertyValue $_.value }
        $PSObject | ConvertTo-Json | Out-File $ScriptVariables.RegExpsPath -Encoding ($ScriptVariables.Charset -replace '-','')
        $ScriptVariables.Regex = $ScriptVariables.Regex = @{} ; (Get-Content $ScriptVariables.RegExpsPath | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables.Regex[$_.Name] = $_.Value } | Sort Name
        $Output += '<form id="AutoSubmit" action="/Admin?Regex" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>'
    }
}
elseif ( $RequestArgs -match '^ResetRegex$' ) {
    if ( $AdminAccess ) {
        Copy-Item -Path ($ScriptVariables.RegExpsPath -replace 'regexps.json','regexps_default.json') -Destination $ScriptVariables.RegExpsPath -Force
        $ScriptVariables.Regex = $ScriptVariables.Regex = @{} ; (Get-Content $ScriptVariables.RegExpsPath | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables.Regex[$_.Name] = $_.Value } | Sort Name
        $Output += '<form id="AutoSubmit" action="/Admin?Regex" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>'
    }
}
elseif ( $RequestArgs -match '^ResetLogo$' ) {
    if ( $AdminAccess ) {
        $([convert]::ToBase64String((get-content ($ScriptVariables.ScriptPath + 'images\logo_default.png') -encoding byte))) | out-file ($ScriptVariables.ScriptPath + 'images\logo_base64.txt')
        $ScriptVariables.Logo = Get-Content ($ScriptVariables.ScriptPath + 'images\logo_base64.txt')
        $Output += '<form id="AutoSubmit" action="/Admin?Regex" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>'    
    }
}
elseif ( $RequestArgs -match '^UpdateSettings$' ) {
    if ( $AdminAccess ) {
        if ( $Language ) {
            if ( $Language -ne $ScriptVariables.Language ) {
                if ( $Language -match "^[a-z]{2}-[a-z]{2}$" ) {
                    (Get-Content ($ScriptVariables.ScriptPath + 'base_settings.json')).replace('"' + $ScriptVariables.Language + '"','"' + $Language + '"') | Out-File ($ScriptVariables.ScriptPath + 'base_settings.json') -Encoding ($ScriptVariables.Charset -replace '-','')
                    $ScriptVariables.Language = $Language
                    $ScriptVariables.Text = $ScriptVariables.Text = @{} ; (Get-Content ($ScriptVariables.LanguagePath + $Language + '.json') | ConvertFrom-Json).PSObject.Properties | foreach { $ScriptVariables.Text[$_.Name] = $_.Value } | Sort Name
                }
            }
        }
        if ( $LogoWidth -match "^[a-z0-9\%]+$" ) {
            $Property = 'LogoWidth'
            $PropertyValue = $LogoWidth
            $CurrentRow = [regex]::match((Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')),"`"$Property`".[^,]*").Value -replace ' }',''
            $NewRow = $CurrentRow -replace [regex]::match($CurrentRow,"(?<=$Property\`":\s* \`").[^`"]*").Value, $PropertyValue
            (Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')).replace($CurrentRow,$NewRow) | Out-File ($ScriptVariables.SettingsPath + 'custom_settings.json') -Encoding ($ScriptVariables.Charset -replace '-','')
            $ScriptVariables.LogoWidth = $LogoWidth
        }
        if ( $LogRows -match "^[0-9]+$" ){
            $Property = 'LogRows'
            $PropertyValue = $LogRows
            $CurrentRow = [regex]::match((Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')),"`"$Property`".[^,]*").Value -replace ' }',''
            $NewRow = $CurrentRow -replace [regex]::match($CurrentRow,"(?<=$Property\`":\s* \`").[^`"]*").Value, $PropertyValue
            (Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')).replace($CurrentRow,$NewRow) | Out-File ($ScriptVariables.SettingsPath + 'custom_settings.json') -Encoding ($ScriptVariables.Charset -replace '-','')
            $ScriptVariables.LogRows = $LogRows
        }
        if ( $Logo ) {
            $Logo | Out-File ($ScriptVariables.ScriptPath + '\images\logo_base64.txt')
            $ScriptVariables.Logo = Get-Content ($ScriptVariables.ScriptPath + '\images\logo_base64.txt')
        }
        if ( $AllowPersonalLinks -ne $ScriptVariables.AllowPersonalLinks ) {
            if ( $AllowPersonalLinks -ne $true ) { $AllowPersonalLinks = $false }
            $Property = 'AllowPersonalLinks'
            $PropertyValue = $AllowPersonalLinks
            $CurrentRow = [regex]::match((Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')),"`"$Property`".[^,]*").Value -replace ' }',''
            $NewRow = $CurrentRow -replace [regex]::match($CurrentRow,"(?<=$Property\`":\s* \`").[^`"]*").Value, $PropertyValue
            (Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')).replace($CurrentRow,$NewRow) | Out-File ($ScriptVariables.SettingsPath + 'custom_settings.json') -Encoding ($ScriptVariables.Charset -replace '-','')
            $ScriptVariables.AllowPersonalLinks = $AllowPersonalLinks
        }
        if ( $AllowPersonalTheme -ne $ScriptVariables.AllowPersonalTheme ) {
            if ( $AllowPersonalTheme -ne $true ) { $AllowPersonalTheme = $false }
            $Property = 'AllowPersonalTheme'
            $PropertyValue = $AllowPersonalTheme
            $CurrentRow = [regex]::match((Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')),"`"$Property`".[^,]*").Value -replace ' }',''
            $NewRow = $CurrentRow -replace [regex]::match($CurrentRow,"(?<=$Property\`":\s* \`").[^`"]*").Value, $PropertyValue
            (Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')).replace($CurrentRow,$NewRow) | Out-File ($ScriptVariables.SettingsPath + 'custom_settings.json') -Encoding ($ScriptVariables.Charset -replace '-','')
            $ScriptVariables.AllowPersonalTheme = $AllowPersonalTheme
        }
        if ( $ShowFooter -ne $ScriptVariables.ShowFooter ) {
            if ( $ShowFooter -ne $true ) { $ShowFooter = $false }
            $Property = 'ShowFooter'
            $PropertyValue = $ShowFooter
            $CurrentRow = [regex]::match((Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')),"`"$Property`".[^,]*").Value -replace ' }',''
            $NewRow = $CurrentRow -replace [regex]::match($CurrentRow,"(?<=$Property\`":\s* \`").[^`"]*").Value, $PropertyValue
            (Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')).replace($CurrentRow,$NewRow) | Out-File ($ScriptVariables.SettingsPath + 'custom_settings.json') -Encoding ($ScriptVariables.Charset -replace '-','')
            $ScriptVariables.ShowFooter = $ShowFooter
        }
        if ( $Theme ) {
            if ( $Theme -ne $ScriptVariables.Theme ) {
                $Property = 'Theme'
                $PropertyValue = $Theme
                $CurrentRow = [regex]::match((Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')),"`"$Property`".[^,]*").Value -replace ' }',''
                $NewRow = $CurrentRow -replace [regex]::match($CurrentRow,"(?<=$Property\`":\s* \`").[^`"]*").Value, $PropertyValue
                (Get-Content ($ScriptVariables.SettingsPath + 'custom_settings.json')).replace($CurrentRow,$NewRow) | Out-File ($ScriptVariables.SettingsPath + 'custom_settings.json') -Encoding ($ScriptVariables.Charset -replace '-','')
                $ScriptVariables.Theme = $Theme
                $ScriptVariables.CSSpath = $ScriptVariables.ScriptPath + 'style\' + $ScriptVariables.Theme + '.css'
            }
        }
        $Output += '<form id="AutoSubmit" action="/Admin?Logo" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>'
     }
}
elseif ( $RequestArgs -match '^SetTheme$' ) {
}
$Output += @"
  <script type="text/javascript" nonce="{{nonce}}">
    function formAutoSubmit () {
      var frm = document.getElementById("AutoSubmit");
      frm.submit();
    }
    window.onload = formAutoSubmit;
  </script>
"@
$Output