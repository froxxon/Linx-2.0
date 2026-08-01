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
    $PersonalPath  = "$($ScriptVariables.PersonalPath)\$CurrentUser.csv"
    $LinksPersonal = Import-CSV $PersonalPath -Delimiter $ScriptVariables.CSVDelimiter
    #endregion
$SelectThemes = Get-ThemeOptions $CurrentUser

[void]$HTML.AppendLine('<header>')
[void]$HTML.AppendLine('<nav align="left"><a href="' + $ScriptVariables.ServerURL + '/Admin?new">' + $ScriptVariables.Text.AdmNewLink + '</a><a href="' + $ScriptVariables.ServerURL + '/">' + $ScriptVariables.Text.StartPage + '</a>' + $AdminLink + '</nav>')
if ( $ScriptVariables.AllowPersonalTheme -eq $true ) {
    [void]$HTML.AppendLine('<div><select name="Theme" id="themeSelect" style="width: 200px;" class="SelTheme">' + $SelectThemes + '</select></div>')
}
[void]$HTML.AppendLine('</header>')
[void]$HTML.AppendLine('<table id="main" align="center">')
[void]$HTML.AppendLine('<tr><td>')
[void]$HTML.AppendLine('<table align="center" class="innerTable">')
if ( !$RequestArgs ) {
    [void]$HTML.AppendLine('<tr><td><input type="text" id="inputFilter" placeholder="' + $ScriptVariables.Text.FilterText + '" autofocus></td></tr>')
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table align="center" data-name="mytable" id="filteredTable" class="hover innerTable">')
    [void]$HTML.AppendLine('<tr><th align="left" width="35%">' + $ScriptVariables.Text.LblName + '</th><th width="35%">' + $ScriptVariables.Text.LblDescription + '</th><th width="15%">' + $ScriptVariables.Text.LblCategory + '</th><th width="15%"></th></tr>')
    foreach ( $Link in $LinksPersonal | Sort-Object Name ) {
        $EditColumn = '<td><a href="' + $ScriptVariables.ServerURL + '/Personal?' + $Link.ID + '">' + $ScriptVariables.Text.Edit + '</a></td>'
        
        $TagTips = $null
        if ( $Link.Tags -ne '' ) {
            $TagTips = '<br><br><b>' + $ScriptVariables.Text.LblTags + ':</b><br>' + $($Link.Tags)
        }
        else {
            $TagTips = '<br><br><b>' + $ScriptVariables.Text.LblTags + ':</b><br><font class="tooltipempty"><i>-</i></font>'
        }
        
        $NotesTips = $null
        if ( $Link.Notes -ne '' ) {
            $NotesTips = '<br><br><b>' + $ScriptVariables.Text.LblNotes + ':</b><br>' + $($Link.Notes)
        }
        else {
            $NotesTips = '<br><br><b>' + $ScriptVariables.Text.LblNotes + ':</b><br><font class="tooltipempty"><i>-</i></font>'
        }
        
        $TooltipText = "$TagTips$NotesTips"
        [void]$HTML.AppendLine('<tr><td align="left"><div class="tooltip"><a href="' + $Link.URL + '" target="_blank"/>' + $Link.Name + '</a><span class="tooltiptext">' + $TooltipText + '</span></div></td><td>' + $Link.Description + '</td><td>' + $Link.Category + '</td><td class="hiddenColumn">' + $Link.Name + $Link.Tags + '</td>' + $EditColumn + '</tr>')
    }
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
}
elseif ( $RequestArgs -match '^[0-9]{7}$' ) {
    $Link = Select-String -Path $PersonalPath -Pattern $RequestArgs -Encoding $($ScriptVariables.Charset -replace '-','') | Select-Object -ExpandProperty Line | convertfrom-csv -Delimiter $ScriptVariables.CSVDelimiter -Header $((Get-Content $PersonalPath -First 1).Split($ScriptVariables.CSVDelimiter))
    $Categories = @{}
    ($LinksPersonal | Group-Object Category).ForEach({
        $currCat = $_.Name
        $Categories.Add($currCat, @{
            ItemCount = $_.Count
            Short     = $($currCat -replace "$($ScriptVariables.Regex.RgxShortCategory)","")
        })
    })
    $SelectCats = '<option value=""></option>'
    foreach ( $Cat in $Categories.Keys | Sort ) {
        $SelectCats += '<option value="' + $Cat + '">' + $Cat + '</option>'
    }
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table class="innertable">')
    [void]$HTML.AppendLine('<form id="frmSaveLink" action="/ManageLink" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '">')
    [void]$HTML.AppendLine('<tr><td>' + $ScriptVariables.Text.LblName + '</td><td width="100%"><input type=text name="Name" value="' + $Link.Name + '" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdName + '" maxlength="128" pattern="' + $ScriptVariables.Regex.RgxName + '" required></td></tr>')
    [void]$HTML.AppendLine('<tr><td>' + $ScriptVariables.Text.LblURL + '</td><td><input type=url name="URL" value="' + $Link.URL + '" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdURL + '" required></td></tr>')
    [void]$HTML.AppendLine('<tr><td>' + $ScriptVariables.Text.LblDescription + '</td><td><input type=text value="' + $Link.Description + '" name="Description" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdDescription + '" pattern="' + $ScriptVariables.Regex.RgxDescription + '"></td></tr>')
    [void]$HTML.AppendLine('<tr><td>' + $ScriptVariables.Text.LblCategory + '</td><td><input type="text" value="' + $Link.Category + '" class="inputFilter" name="Category" list="Categories" pattern="' + $ScriptVariables.Regex.RgxCategory + '" placeholder="' + $ScriptVariables.Text.PhdCategory + '" required/><datalist id="Categories">' + $SelectCats + '</datalist></td></tr>')
    [void]$HTML.AppendLine('<tr><td>' + $ScriptVariables.Text.LblTags + '</td><td><input type="text" value="' + $Link.Tags + '" class="inputFilter" name="Tags" pattern="' + $ScriptVariables.Regex.RgxTags + '" placeholder="' + $ScriptVariables.Text.PhdTags + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td>' + $ScriptVariables.Text.LblNotes + '</td><td><input type="text" value="' + $Link.Notes + '" class="inputFilter" name="Notes" pattern="' + $ScriptVariables.Regex.RgxNotes + '" placeholder="' + $ScriptVariables.Text.PhdNotes + '"/></td></tr>')
    [void]$HTML.AppendLine('<input hidden name="Type" value="update" type="text"/>')
    [void]$HTML.AppendLine('<input hidden name="ID" value="' + $RequestArgs + '" type="text"/>')
    [void]$HTML.AppendLine('</form>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
    [void]$HTML.AppendLine('<table class="innertable">')
    [void]$HTML.AppendLine('<tr><td><a title="' + $ScriptVariables.Text.RemoveLinkWarning + '" href="/Personal?remove' + $RequestArgs + '" align="center" class="removelink">' + $ScriptVariables.Text.RemoveLink + '</a></td><td align="right"><button id="btnRemoveLink" class="btn" type="button">' + $ScriptVariables.Text.CancelBtn + '</button><input class="btn" type="Submit" form="frmSaveLink" value="' + $ScriptVariables.Text.UpdateBtn + '"></td></tr>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
}
elseif ( $RequestArgs -match '^remove[0-9]{7}$' ) {
    $CurrentContent = $(Get-Content -Path $PersonalPath | Select-String -Pattern "^$($RequestArgs -replace 'remove','')\$($ScriptVariables.CSVDelimiter)" -Encoding $($ScriptVariables.Charset -replace '-','')).Line
    if ( $CurrentContent ) {
        $LinkName = $($CurrentContent.Split($ScriptVariables.CSVDelimiter).Trim())[1]
        Set-Content -Path $PersonalPath -Encoding $($ScriptVariables.Charset -replace '-','') -Value (Get-Content -Path $PersonalPath -Encoding $($ScriptVariables.Charset -replace '-','') | Select-String -Pattern "^$($RequestArgs -replace 'remove','')\$($ScriptVariables.CSVDelimiter)" -Encoding $($ScriptVariables.Charset -replace '-','') -NotMatch)
        [void]$HTML.AppendLine('<form id="AutoSubmit" action="/Personal" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>')
    }
}
else { exit }
[void]$HTML.AppendLine( @"
      </table>
    </td></tr>
  </table>
  $( if ( $ScriptVariables.ShowFooter -eq $true ) { '<img width="50em" style="vertical-align: middle;" src="data:image/png;base64, ' + $(Get-Content ($ScriptVariables.ScriptPath + 'images\linx_base64.txt')) + '"/><pre style="vertical-align: middle;"> version ' + $($ScriptVariables.Version) + '</pre>' })
  <script src="/personal.js" type="text/javascript" nonce="{{nonce}}"></script>
  <script src="/scripts.js" type="text/javascript" nonce="{{nonce}}"></script>
</body>
</html>
"@ )
$HTML.ToString()