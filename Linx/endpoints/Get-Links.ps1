param ( $RequestArgs )

#region Get user information
    $CurrentUser = $null
    $CurrentUser = $($Request.Headers['X-Authenticated-User'] -replace ("$($ScriptVariables.Domain)\\",''))
    if ( $CurrentUser -notmatch '^[a-zA-Z0-9\.\-_\$]{1,64}$' ) { return "$($ScriptVariables.Text.AccessDenied)" }
    
    try { '' | Out-File (Join-Path -Path $ScriptVariables.PersonalPath -ChildPath "$($CurrentUser).accesstime" ) } catch {}

    $PersonalCSSLink = $null
    if ( $ScriptVariables.AllowPersonalTheme -eq $true ) { $PersonalCSSLink = (Get-ChildItem (Join-Path -Path $ScriptVariables.PersonalPath -ChildPath "$($CurrentUser)-*.css_link")).BaseName }
    if ( $PersonalCSSLink ) {
        if ( Test-Path (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath "style\$($PersonalCSSLink -replace "$CurrentUser-",'').css" ) ) {
            $CSS = Get-Content (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath "style\$($PersonalCSSLink -replace "$CurrentUser-",'').css" )            
        }
        else { Remove-Item (Join-Path -Path $ScriptVariables.PersonalPath -ChildPath "$($CurrentUser)-*.css_link") -Force }
    }
    if ( $null -eq $CSS ) { $CSS = Get-Content $ScriptVariables.CSSpath }
    
    $HTML = [System.Text.StringBuilder]::new()
    [void]$HTML.AppendLine($(Get-HTMLHead $CSS))
    $MainUser = Get-MainUser $CurrentUser
    if ( !$MainUser ) {
        [void]$HTML.AppendLine('<br>' + $ScriptVariables.Text.AccessDenied)
        return $HTML.ToString()
    }
#endregion
#region Get additional rights in Linx
    foreach ( $group in $EditMembers ) {
        if ( $group -in $MainUser.memberof ) {
            $AdminLink = '<a href="' + $ScriptVariables.ServerURL + '/Admin">Admin</a>'
            break
        }
    }
    if ( $MainUser.memberof -eq "$($ScriptVariables.EditGroup)" ) { $AdminLink = '<a href="' + $ScriptVariables.ServerURL + '/Admin">Admin</a>' }
    foreach ( $group in $AdminMembers ) {
        if ( $group -in $MainUser.memberof ) {
            $AdminLink = '<a href="' + $ScriptVariables.ServerURL + '/Admin">Admin</a>'
            break
        }
    }
    if ( $MainUser.memberof -eq "$($ScriptVariables.AdminGroup)" ) { $AdminLink = '<a href="' + $ScriptVariables.ServerURL + '/Admin">Admin</a>' }
#endregion
#region Get Links
    if ( $ScriptVariables.AllowPersonalLinks -eq $true ) {
        $PersonalPath = Join-Path -Path $ScriptVariables.PersonalPath -ChildPath "$($CurrentUser).csv"
        if ( Test-Path $PersonalPath ) {
            if ( ( Get-Content $PersonalPath -first 2).count -gt 1 ) {
                $LinksPersonal = Import-CSV $PersonalPath -Delimiter $ScriptVariables.CSVDelimiter
                $PersonalLink = '<a href="' + $ScriptVariables.ServerURL + '/Personal">' + $ScriptVariables.Text.PersonalLink + '</a>'
            }
        }
    }
#endregion
$SelectThemes = Get-ThemeOptions $CurrentUser

[void]$HTML.AppendLine('<header>')
[void]$HTML.AppendLine('<nav align="left"><a href="' + $ScriptVariables.ServerURL + '/Admin?new">' + $ScriptVariables.Text.AdmNewLink + '</a>' + $PersonalLink + $AdminLink + '</nav>')
if ( $ScriptVariables.AllowPersonalTheme -eq $true ) {
    [void]$HTML.AppendLine('<div><select name="Theme" id="themeSelect" style="width: 200px;" class="SelTheme"><option style="display:none;" selected="true" disabled="disabled">' + $ScriptVariables.Text.SelectTheme + '</option>' + $SelectThemes + '</select></div>')
}
[void]$HTML.AppendLine('</header>')
[void]$HTML.AppendLine('<table id="main" align="center">')
[void]$HTML.AppendLine('<tr><td>')
[void]$HTML.AppendLine('<table align="center" class="innerTable">')
if ( !$RequestArgs ) {
    $CurrentLinks = $Links 
    if ( $LinksPersonal ) { $CurrentLinks += $LinksPersonal }
    $Categories = @{}
    ($CurrentLinks | Group-Object Category).ForEach({
        $currCat = $_.Name
        $Categories.Add($currCat, @{
            ItemCount = $_.Count
            Short     = $($currCat -replace "$($ScriptVariables.Regex.RgxShortCategory)","")
        })
    })
    [void]$HTML.AppendLine('<tr><td><input type="text" id="inputFilter" placeholder="' + $ScriptVariables.Text.FilterText + '" autofocus><br>')
    [void]$HTML.AppendLine('<select id="JumpToCat" class="selCats"><option style="display:none;" selected="true" disabled="disabled">' + $ScriptVariables.Text.JumpToCatText + '</option>')
    [void]$HTML.AppendLine($( foreach ( $Cat in $Categories.Keys | Sort ) { '<option value="anchor-' + $Categories.$Cat.Short + '">' + $Cat + ' (' + $Categories.$Cat.ItemCount + ')</option>' }))
    [void]$HTML.AppendLine('</select>')
    [void]$HTML.AppendLine('</td></tr>')
    if ( $ScriptVariables.Text.UserPageText ) {
        [void]$HTML.AppendLine('<tr><td><i>' + $ScriptVariables.Text.UserPageText + '</i></td></tr>')
    }
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table align="center" data-name="mytable" id="filteredTable" class="hover innerTable">')
    foreach ( $Cat in $Categories.Keys | Sort ) {
        [void]$HTML.AppendLine('<tr class="header expand"><th colspan="3" class="category"><a class="catheader" name="anchor-' + $Categories.$Cat.Short + '">' + $Cat + '<span class="sign"/></a></th></tr>')
        foreach ( $Link in $CurrentLinks | Where { $_.Category -eq $Cat } | Sort-Object Name ) {
            if ( $Link.Disabled -notmatch "^true$" ) {

                $RoleTips = $null
                if ( $Link.ID.Length -eq 8 ) {
                    if ( $Link.Role -ne '' ) {
                        $RoleTips = '<br><br><b>' + $ScriptVariables.Text.DisplayFor + ':</b><br>' + $Link.Role -replace ',','<br>'
                    }
                    else {
                        $RoleTips = '<br><br><b>' + $ScriptVariables.Text.DisplayFor + ':</b><br>' + $ScriptVariables.Text.Everyone
                    }
                }
                
                $TagTips = $null
                if ( $Link.Tags  -ne '' ) {
                    $TagTips = '<br><br><b>' + $ScriptVariables.Text.LblTags + ':</b><br>' + $Link.Tags
                }
                else {
                    $TagTips = '<br><br><b>' + $ScriptVariables.Text.LblTags + ':</b><br><font class="tooltipempty"><i>-</i></font>'
                }
                
                $ContactTips = $null
                if ( $Link.ID.Length -eq 8 ) {
                    if ( $Link.Contact  -ne '' ) {
                        $ContactTips = '<br><br><b>' + $ScriptVariables.Text.LblContact + ':</b><br>' + $Link.Contact
                    }
                    else {
                        $ContactTips = '<br><br><b>' + $ScriptVariables.Text.LblContact + ':</b><br><font class="tooltipempty"><i>-</i></font>'
                    }
                }

                $NotesTips = $null
                if ( $Link.Notes  -ne '' ) {
                    $NotesTips = '<br><br><b>' + $ScriptVariables.Text.LblNotes + ':</b><br>' + $Link.Notes
                }
                else {
                    $NotesTips = '<br><br><b>' + $ScriptVariables.Text.LblNotes + ':</b><br><font class="tooltipempty"><i>-</i></font>'
                }
                
                $TooltipText = "$RoleTips$TagTips$ContactTips$NotesTips"
                if ( $Link.Role  -ne '' ) {
                    foreach ( $Role in $($Link.Role.Split(",")) ) {
                        if ( $MainUser.memberof -match "^CN=$Role" ) {
                            [void]$HTML.AppendLine('<tr><td width="40%" align="left"><div class="tooltip"><a href="' + $Link.URL + '" target="_blank"/>' + $Link.Name + '</a><span class="tooltiptext">' + $TooltipText + '</span></div></td><td align="right">' + $Link.Description + '</td><td class="hiddenColumn">' + $Link.Name + $Link.Tags + '</td></tr>')
                            break
                        }
                    }
                }
                else {
                    $PersonalClass = $null
                    if ( $Link.ID.Length -ne 8 ) {
                        $PersonalTip   = '<b><i><font class="personal">' + $($ScriptVariables.Text.LblPersonal) + '</font></i></b>'
                        $PersonalClass = 'class="Personal"'
                    }
                    [void]$HTML.AppendLine('<tr><td width="40%" align="left"><div class="tooltip"><a href="' + $Link.URL + '" target="_blank"/><font ' + $PersonalClass + '>' + $Link.Name + '</font></a><span class="tooltiptext">' + $PersonalTip + $TooltipText + '</span></div></td><td align="right">' + $Link.Description + '</td><td class="hiddenColumn">' + $Link.Name + $Link.Tags + '</td></tr>')
                }
            }
        }

        $SelectThemes = @()
        foreach ( $Theme in $AvailableThemes ) {
            if ( $PersonalCSSLink -match ($Theme -replace 'theme-','') ) { $Selected = 'Selected' }
            else {
                if ( !$PersonalCSSLink -and $Theme -eq $ScriptVariables.Theme ) { $Selected = 'selected' }
                else { $Selected = $null }
            }
            if ( $Theme -eq $ScriptVariables.Theme ) { $DefaultTheme = " ($($ScriptVariables.Text.DefaultText))" }
            else { $DefaultTheme = $null }
            $SelectThemes += '<option value="' + $Theme + '" ' + $Selected + '>' + ($Theme -replace '_',' ' -replace 'theme-','') + $DefaultTheme + '</option>'
        }
        $PersonalCSSLink = $null
        $SelectThemes = $SelectThemes -join ''
    }
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
}
elseif ( $RequestArgs -match '^SelectTheme' ) {
    $SelectedTheme = [regex]::match($RequestArgs,"(?<=&).[^&]*")
    if ( $SelectedTheme -match "^$($ScriptVariables.Theme)$" ) { Remove-Item (Join-Path -Path $ScriptVariables.PersonalPath -ChildPath "$($CurrentUser)-*.css_link") -Force }
    else {
        Remove-Item (Join-Path -Path $ScriptVariables.PersonalPath -ChildPath "$($CurrentUser)-*.css_link") -Force
        '' | Out-File (Join-Path $ScriptVariables.PersonalPath -ChildPath "$($CurrentUser)-$($SelectedTheme).css_link") -Force
    }
    [void]$HTML.AppendLine('<form id="AutoSubmit" action="/" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>')
    [void]$HTML.AppendLine('<script src="/scripts.js" type="text/javascript" nonce="{{nonce}}"></script>')
    [void]$HTML.AppendLine('</body></html>')
    return $HTML.ToString()
}
[void]$HTML.AppendLine( @"
      </table>
    </td></tr>
  </table>
  $( if ( $ScriptVariables.ShowFooter -eq $true ) { '<img alt="footer" width="50em" style="vertical-align: middle;" src="data:image/png;base64, ' + $(Get-Content ($ScriptVariables.ScriptPath + 'images\linx_base64.txt')) + '"/><pre style="vertical-align: middle;"> version ' + $($ScriptVariables.Version) + '</pre>' })
  <script src="/scripts.js" type="text/javascript" nonce="{{nonce}}"></script>
</body>
</html>
"@ )
$HTML.ToString()