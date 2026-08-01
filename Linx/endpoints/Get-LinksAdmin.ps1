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
        if ( $group -in $MainUser.memberof -or $group -eq $MainUser.distinguishedname ) {
            $Edit = '<th width="5%"></th>'
            $EditLinks += '<a href="' + $ScriptVariables.ServerURL + '/">' + $ScriptVariables.Text.StartPage + '</a><a href="' + $ScriptVariables.ServerURL + '/Admin">' + $ScriptVariables.Text.AdmOverview + '</a><a href="' + $ScriptVariables.ServerURL + '/Admin?Log">' + $ScriptVariables.Text.AdmLog + '</a>'
            break
        }
    }
    foreach ( $group in $AdminMembers ) {
        if ( $group -in $MainUser.memberof -or $group -eq $MainUser.distinguishedname ) {
            $Edit = '<th width="5%"></th>'
            $Admin = "<th></th>"
            $AdminLinks += '<a href="' + $ScriptVariables.ServerURL + '/">' + $ScriptVariables.Text.StartPage + '</a><a href="' + $ScriptVariables.ServerURL + '/Admin">' + $ScriptVariables.Text.AdmOverview + '</a><a href="' + $ScriptVariables.ServerURL + '/Admin?Log">' + $ScriptVariables.Text.AdmLog + '</a><a href="' + $ScriptVariables.ServerURL + '/Admin?Text">Text</a><a href="' + $ScriptVariables.ServerURL + '/Admin?Regex">Regex</a><a href="' + $ScriptVariables.ServerURL + '/Admin?Settings">' + $ScriptVariables.Text.AdmSettings + '</a>'
            break
        }
    }
#endregion
$SelectThemes = Get-ThemeOptions $CurrentUser

[void]$HTML.AppendLine('<header>')
[void]$HTML.AppendLine('<nav align="left"><a href="' + $ScriptVariables.ServerURL + '/Admin?new">' + $ScriptVariables.Text.AdmNewLink + '</a>' + $EditLinks + $AdminLinks + '</nav>')
if ( $ScriptVariables.AllowPersonalTheme -eq $true ) {
    [void]$HTML.AppendLine('<div><select name="Theme" id="themeSelect" style="width: 200px;" class="SelTheme">' + $SelectThemes + '</select></div>')
}
[void]$HTML.AppendLine('</header>')
[void]$HTML.AppendLine('<table id="main" align="center">')
[void]$HTML.AppendLine('<tr><td>')
[void]$HTML.AppendLine('<table align="center" class="innerTable">')
if ( !$RequestArgs ) {
    if ( ! $Edit ) { exit }
    [void]$HTML.AppendLine( @"
    <tr><td><input type="text" id="inputFilter" placeholder="$($ScriptVariables.Text.FilterText)" autofocus></td></tr>
    <tr><td>
      <table align="center" data-name="mytable" id="filteredTable" class="hover innerTable">
        <thead><tr><th align="left" width="30%">$($ScriptVariables.Text.LblName)</th><th width="30%">$($ScriptVariables.Text.LblDescription)</th><th width="15%">$($ScriptVariables.Text.LblCategory)</th><th width="15%">$($ScriptVariables.Text.LblRole)</th><th width="5%">$($ScriptVariables.Text.LblShowLink)</th>$Edit</tr></thead>
          <tbody>
"@ )
    foreach ( $Link in $Links | Sort-Object Name ) {
        if ( $Link.Disabled -match "^true$" ) {
            $Enabled = '<font class="admlinkdisabled">' + $ScriptVariables.Text.IsNo + '</font>'
        }
        else {
            $Enabled = '<font class="admlinkenabled">' + $ScriptVariables.Text.IsYes + '</font>'
        }
        
        $EditColumn = '<td><a href="' + $ScriptVariables.ServerURL + '/Admin?' + $Link.ID + '">' + $ScriptVariables.Text.Edit + '</a></td>'
        
        $RoleTips = $null
        if ( $Link.Role -ne '' ) {
            $RoleTips = '<br><br><b>' + $ScriptVariables.Text.DisplayFor + ':</b><br>' + $($Link.Role -replace ',','<br>')
        }
        else {
            $RoleTips = '<br><br><b>' + $ScriptVariables.Text.DisplayFor + ':</b><br>' + $ScriptVariables.Text.Everyone
        }
        
        $TagTips = $null
        if ( $Link.Tags -ne '' ) {
            $TagTips = '<br><br><b>' + $ScriptVariables.Text.LblTags + ':</b><br>' + $($Link.Tags)
        }
        else {
            $TagTips = '<br><br><b>' + $ScriptVariables.Text.LblTags + ':</b><br><font class="tooltipempty"><i>-</i></font>'
        }
        
        $ContactTips = $null
        if ( $Link.Contact -ne '' ) {
            $ContactTips = '<br><br><b>' + $ScriptVariables.Text.LblContact + ':</b><br>' + $($Link.Contact)
        }
        else {
            $ContactTips = '<br><br><b>' + $ScriptVariables.Text.LblContact + ':</b><br><font class="tooltipempty"><i>-</i></font>'
        }
        
        $NotesTips = $null
        if ( $Link.Notes -ne '' ) {
            $NotesTips = '<br><br><b>' + $ScriptVariables.Text.LblNotes + ':</b><br>' + $($Link.Notes)
        }
        else {
            $NotesTips = '<br><br><b>' + $ScriptVariables.Text.LblNotes + ':</b><br><font class="tooltipempty"><i>-</i></font>'
        }
        
        $TooltipText = "$RoleTips$TagTips$ContactTips$NotesTips"
        [void]$HTML.AppendLine('<tr><td width="10%" align="left"><div class="tooltip"><a href="' + $Link.URL + '" target="_blank"/>' + $Link.Name + '</a><span class="tooltiptext">' + $TooltipText + '</span></div></td><td>' + $Link.Description + '</td><td class="hiddenColumn">' + $Link.Name + $Link.Tags + '</td><td>' + $Link.Category + '</td><td>' + $Link.Role + '</td><td>' + $($Enabled) + '</td><td class="hiddenColumn">' + $Link.Name + $Link.Tags + '</td>' + $EditColumn + '</tr>')
    }
    [void]$HTML.AppendLine('</tbody>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
}
elseif ( $RequestArgs -match '^Log$' ) {
    if ( ! $Edit ) { exit }
    [void]$HTML.AppendLine( @"
    <tr><td><input type="text" id="inputFilterLog" class="inputFilterLog" placeholder="$($ScriptVariables.Text.FilterText)" autofocus></td></tr>
    <tr><td>
      <table align="center" data-name="mytable" id="filteredTable" class="hover innerTable">
        <tr><th>$($ScriptVariables.LogRows) $($ScriptVariables.Text.LogText):</th></tr>
"@ )

    [array]$Logs = Get-Content "$($ScriptVariables.LogChangesPath)" -tail $ScriptVariables.LogRows -Encoding $($ScriptVariables.Charset -replace '-','') | Select -Skip 1 | sort -Descending
    foreach ( $Log in $Logs ) {
        if     ( $Log -match " created "  ) { $Log = $Log -replace (' created ','<font class="logobjCreated"> <b>created</b> </font>') }
        elseif ( $Log -match " modified " ) { $Log = $Log -replace (' modified ','<font class="logobjModified"> <b>modified</b> </font>') }
        elseif ( $Log -match " removed "  ) { $Log = $Log -replace (' removed ','<font class="logobjRemoved"> <b>removed</b> </font>') }
        [void]$HTML.AppendLine('<tr><td align="left">' + $Log + '</td></tr>')
    }

    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table align="center" class="innerTable">')
    [void]$HTML.AppendLine('<tr><th colspan="3" >' + $ScriptVariables.Text.Visitors + '</th></tr>')
    [void]$HTML.AppendLine('<tr><td width="33%">' + $ScriptVariables.Text.IsToday + '</td><td width="33%">7 ' + $ScriptVariables.Text.IsDays + '</td><td width="33%">30 ' + $ScriptVariables.Text.IsDays + '</td></tr>')
    $AccessTimes = Get-Childitem ($ScriptVariables.PersonalPath + '\*.accesstime') | Select LastWriteTime
    $Users1Day = @($AccessTimes | Where { $_.LastWriteTime -gt (Get-Date).Date }).Count
    $Users7Days = @($AccessTimes | Where { $_.LastWriteTime -gt (Get-Date).Date.AddDays(-7) }).Count
    $Users30Days = @($AccessTimes | Where { $_.LastWriteTime -gt (Get-Date).Date.AddDays(-30) }).Count
    [void]$HTML.AppendLine('<tr><td>' + $Users1Day + '</td><td>' + $Users7Days + '</td><td>' + $Users30Days + '</td></tr>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
}
elseif ( $RequestArgs -match '^[0-9]{8}$' ) {
    if ( ! $Edit ) { exit }
    $Link = Select-String -Path $ScriptVariables.LinksFilePath -Pattern $RequestArgs -Encoding $($ScriptVariables.Charset -replace '-','') | Select-Object -ExpandProperty Line | convertfrom-csv -Delimiter $ScriptVariables.CSVDelimiter -Header $((Get-Content $ScriptVariables.LinksFilePath -First 1).Split($ScriptVariables.CSVDelimiter))
    $Categories = @{}
    ($Links | Group-Object Category).ForEach({
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
    if ( $Link.Disabled -match "^true$" ) {
        $Enabled = ''
    }
    else { $Enabled = 'checked' }
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table class="innerTable">')
    [void]$HTML.AppendLine('<form id="frmSaveLink" action="/ManageLink" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '">')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblName + '</td><td width="100%"><input type=text name="Name" value="' + $Link.Name + '" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdName + '" maxlength="128" pattern="' + $ScriptVariables.Regex.RgxName + '" required></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblURL + '</td><td><input type=url name="URL" value="' + $Link.URL + '" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdURL + '" required></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblDescription + '</td><td><input type=text value="' + $Link.Description + '" name="Description" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdDescription + '" pattern="' + $ScriptVariables.Regex.RgxDescription + '"></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblCategory + '</td><td><input type="text" value="' + $Link.Category + '" class="inputFilter" name="Category" list="Categories" pattern="' + $ScriptVariables.Regex.RgxCategory + '" placeholder="' + $ScriptVariables.Text.PhdCategory + '" required/><datalist id="Categories">' + $SelectCats + '</datalist></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblRole + '</td><td><input type="text" value="' + $Link.Role + '" class="inputFilter" name="Role" pattern="' + $ScriptVariables.Regex.RgxRole + '" placeholder="' + $ScriptVariables.Text.PhdRole + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblTags + '</td><td><input type="text" value="' + $Link.Tags + '" class="inputFilter" name="Tags" pattern="' + $ScriptVariables.Regex.RgxTags + '" placeholder="' + $ScriptVariables.Text.PhdTags + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblContact + '</td><td><input type="text" value="' + $Link.Contact + '" class="inputFilter" name="Contact" pattern="' + $ScriptVariables.Regex.RgxContact + '" placeholder="' + $ScriptVariables.Text.PhdContact + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblNotes + '</td><td><input type="text" value="' + $Link.Notes + '" class="inputFilter" name="Notes" pattern="' + $ScriptVariables.Regex.RgxNotes + '" placeholder="' + $ScriptVariables.Text.PhdNotes + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%">' + $ScriptVariables.Text.LblShowLink + '</td><td align="right"><label class="switch"><input type=checkbox id="chkEnabled" name="Enabled" value="checked" ' + $Enabled + '><span class="slider"></span></label></td></tr>')
    [void]$HTML.AppendLine('<input hidden name="Type" value="update" type="text"/>')
    [void]$HTML.AppendLine('<input hidden name="ID" value="' + $RequestArgs + '" type="text"/>')
    [void]$HTML.AppendLine('</form>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
    [void]$HTML.AppendLine('<table class="innertable">')
    [void]$HTML.AppendLine('<tr><td><a title="' + $ScriptVariables.Text.RemoveLinkWarning + '" href="/Admin?remove' + $RequestArgs + '" align="center" class="removelink">' + $ScriptVariables.Text.RemoveLink + '</a></td><td align="right"><button id="btnRemoveLink" class="btn" type="button">' + $ScriptVariables.Text.CancelBtn + '</button><input class="btn" type="Submit" form="frmSaveLink" value="' + $ScriptVariables.Text.UpdateBtn + '"></td></tr>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
}
elseif ( $RequestArgs -match '^new$' ) {
    $Categories = @{}
    ($Links | Group-Object Category).ForEach({
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
    [void]$HTML.AppendLine('<table class="innerTable">')
    [void]$HTML.AppendLine('<form id="frmSaveLink" action="/ManageLink" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '">')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblName + '</td><td width="100%"><input type=text name="Name" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdName + '" maxlength="128" pattern="' + $ScriptVariables.Regex.RgxName + '" required></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblURL + '</td><td><input type=url name="URL" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdURL + '" required></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblDescription + '</td><td><input type=text name="Description" class="inputFilter" placeholder="' + $ScriptVariables.Text.PhdDescription + '" pattern="' + $ScriptVariables.Regex.RgxDescription + '"></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblCategory + '</td><td><input type="text" class="inputFilter" name="Category" list="Categories" pattern="' + $ScriptVariables.Regex.RgxCategory + '" placeholder="' + $ScriptVariables.Text.PhdCategory + '" required/><datalist id="Categories">' + $SelectCats + '</datalist></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblRole + '</td><td><input type="text" class="inputFilter" name="Role" pattern="' + $ScriptVariables.Regex.RgxRole + '" placeholder="' + $ScriptVariables.Text.PhdRole + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblTags + '</td><td><input type="text" class="inputFilter" name="Tags" pattern="' + $ScriptVariables.Regex.RgxTags + '" placeholder="' + $ScriptVariables.Text.PhdTags + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblContact + '</td><td><input type="text" class="inputFilter" name="Contact" pattern="' + $ScriptVariables.Regex.RgxContact + '" placeholder="' + $ScriptVariables.Text.PhdContact + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%;">' + $ScriptVariables.Text.LblNotes + '</td><td><input type="text" class="inputFilter" name="Notes" pattern="' + $ScriptVariables.Regex.RgxNotes + '" placeholder="' + $ScriptVariables.Text.PhdNotes + '"/></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%">' + $ScriptVariables.Text.LblShowLink + '</td><td align="right"><label class="switch"><input type=checkbox id="chkEnabled" name="Enabled" value="checked" checked><span class="slider"></span></label></td></tr>')
    if ( $ScriptVariables.AllowPersonalLinks -eq $true ) {
        [void]$HTML.AppendLine('<tr><td align="left" style="width: 25%">' + $ScriptVariables.Text.LblPersonal + '</td><td align="right"><label class="switch" title="' + $ScriptVariables.Text.PersonalText + '" ><input type=checkbox id="chkPersonal" title="' + $ScriptVariables.Text.PersonalText + '" name="Personal" value="checked"><span class="slider"></span></label></td></tr>')
    }
    [void]$HTML.AppendLine('<input hidden name="Type" value="new" type="text"/>')
    [void]$HTML.AppendLine('</form>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
    [void]$HTML.AppendLine('<tr><td align="right"><button class="btn" id="btnCancel" type="button">' + $ScriptVariables.Text.CancelBtn + '</button><pre>  </pre><input class="btn" type="Submit" form="frmSaveLink" value="' + $ScriptVariables.Text.SaveBtn + '"></td></tr>'   )
}
elseif ( $RequestArgs -match '^remove[0-9]{8}$' ) {
    if ( ! $Edit ) { exit }
    $CurrentContent = $(Get-Content -Path $ScriptVariables.LinksFilePath | Select-String -Pattern "^$($RequestArgs -replace 'remove','')\$($ScriptVariables.CSVDelimiter)" -Encoding $($ScriptVariables.Charset -replace '-','')).Line
    if ( $CurrentContent ) {
        $CurrentContent | Out-File -FilePath $ScriptVariables.RemovedLinksPath -Append
        $LinkName = $($CurrentContent.Split($ScriptVariables.CSVDelimiter).Trim())[1]
        Set-Content -Path $ScriptVariables.LinksFilePath -Encoding $($ScriptVariables.Charset -replace '-','') -Value (Get-Content -Path $ScriptVariables.LinksFilePath -Encoding $($ScriptVariables.Charset -replace '-','') | Select-String -Pattern "^$($RequestArgs -replace 'remove','')\$($ScriptVariables.CSVDelimiter)" -Encoding $($ScriptVariables.Charset -replace '-','') -NotMatch)
        Write-Log -Message "$CurrentUser removed ID $($RequestArgs -replace 'remove','') : $LinkName"
        $global:Links = Import-CSV $ScriptVariables.LinksFilePath -Delimiter $ScriptVariables.CSVDelimiter
    }
    [void]$HTML.AppendLine( '<form id="AutoSubmit" action="/Admin" method="get" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"></form>' )
}
elseif ( $RequestArgs -match '^Text$' ) {
    if ( ! $Admin ) { exit }
    [void]$HTML.AppendLine('<tr><td><input type="text" id="inputFilter" placeholder="' + $ScriptVariables.Text.FilterText + '" autofocus></td></tr>')
    [void]$HTML.AppendLine('<tr><td align="left"><b>' + $ScriptVariables.Text.AwarenessText + '<br><br></b></td></tr>')
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table with="100%" align="center" data-name="mytable" id="filteredTable" class="hover innerTable">')
    [void]$HTML.AppendLine('<form id="frmUpdateText" action="/ManageLink?UpdateText" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '">')
    foreach ( $obj in $ScriptVariables.Text.Keys | Sort ) {
        [void]$HTML.AppendLine('<tr><td width="50%" align="left">' + $obj.trim() + '</td><td width="50%" align="right"><input type="text" name="' + $obj.trim() + '" value="' + $ScriptVariables.Text.$obj.trim() + '"/></td><td class="hiddenColumn">' + $ScriptVariables.Text.$obj.trim() + '</td></tr>')
    }
    [void]$HTML.AppendLine('</form>')
    [void]$HTML.AppendLine('<form id="frmResetText" action="/ManageLink?ResetText" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"/>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr><tr><td>')
    [void]$HTML.AppendLine('<table class="innertable">')
    [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left"><button class="btn reset" form="frmResetText" type="Submit">' + $ScriptVariables.Text.ResetBtn + '</button></td><td style="width: 50%;" align="right"><input class="btn" align="right" form="frmUpdateText" type="Submit" value="' + $ScriptVariables.Text.SaveBtn + '"/></td></tr>')
    [void]$HTML.AppendLine('</table>')
}
elseif ( $RequestArgs -match '^Regex$' ) {
    if ( ! $Admin ) { exit }
    [void]$HTML.AppendLine('<tr><td colspan="2" align="left"><b>' + $ScriptVariables.Text.AwarenessText + '<br><br></b></td></tr>')
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table width="100%" align="center" data-name="mytable" id="filteredTable" class="hover innerTable">')
    [void]$HTML.AppendLine('<form id="frmUpdateRegex" action="/ManageLink?UpdateRegex" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '">')
    foreach ( $obj in $ScriptVariables.Regex.Keys | Sort ) {
        [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left">' + $obj.trim() + '</td><td style="width: 50%;" align="right"><input type="text" name="' + $obj.trim() + '" value="' + $ScriptVariables.Regex.$obj.trim() + '"/></td></td></tr>')
    }
    [void]$HTML.AppendLine('</form>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('<form id="frmResetRegex" action="/ManageLink?ResetRegex" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"/>')
    [void]$HTML.AppendLine('</td></tr><tr><td>')
    [void]$HTML.AppendLine('<table class="innertable">')
    [void]$HTML.AppendLine('<tr><td align="left"><button class="btn reset" form="frmResetRegex" type="Submit">' + $ScriptVariables.Text.ResetBtn + '</button></td><td align="right"><input class="btn" form="frmUpdateRegex" type="Submit" value="' + $ScriptVariables.Text.SaveBtn + '"></td></tr>')
    [void]$HTML.AppendLine('</table>')
}
elseif ( $RequestArgs -match '^Settings$' ) {
    if ( ! $Admin ) { exit }
    [void]$HTML.AppendLine('<form id="frmUpdateSettings" action="/ManageLink?UpdateSettings" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '">')
    $BaseSettings = Get-Content (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'base_settings.json') | ConvertFrom-Json
    [void]$HTML.AppendLine('<tr><td id="cssheader"><b>' + $ScriptVariables.Text.SettingsServer + '</b></td></tr>')
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table align="center" class="hover innerTable">')
    foreach ( $Setting in $BaseSettings.PSObject.Properties ) {
        if ( $Setting.Name -eq 'Language' ) {
            $AvailableLangs = (Get-Childitem $ScriptVariables.LanguagePath -Exclude '*_default.json').BaseName
            $SelectLangs = @()
            foreach ( $Lang in $AvailableLangs | Sort -Unique ) {
                if ( $ScriptVariables.Language -eq $Lang ) {
                    $SelectLangs += '<option value="' + $Lang + '" selected>' + $Lang + '</option>'
                }
                else {
                    $SelectLangs += '<option value="' + $Lang + '">' + $Lang + '</option>'
                }
            }
            [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left"><label>' + $Setting.Name + '</label></td><td style="width: 50%;" align="right"><select class="selLang" name="Language"/>' + $SelectLangs -join '' + '</select></td></tr>')
        }
        else {
            [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left"><label>' + $Setting.Name + '</label></td><td style="width: 50%;" align="right"><input name="' + $Setting.Name + '" type="text" value="' + $Setting.Value + '" disabled/></td></tr>')
        }
    }
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
    $CustomSettings = Get-Content "$($ScriptVariables.SettingsPath)\custom_settings.json" | ConvertFrom-Json
    [void]$HTML.AppendLine('<tr><td id="cssheader" colspan="2"><b>' + $ScriptVariables.Text.SettingsCustom + '</b></td></tr>')
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table align="center" class="hover innerTable">')
    foreach ( $Setting in $CustomSettings.PSObject.Properties ) {
        if ( $Setting.Name -match "(LogRows|LogoWidth)" ) {
            [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left"><label>' + $Setting.Name + '</label></td><td style="width: 50%;" align="right"><input type="text" name="' + $Setting.Name + '" value="' + $Setting.Value + '"/></td></tr>')
        }
        elseif ( $Setting.Name -eq 'Theme' ) {
            $AvailableThemes = (Get-ChildItem (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'style\theme*')).BaseName
            [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left">' + $ScriptVariables.Text.SelectTheme + ' (<i>' + $ScriptVariables.Text.DefaultText +  '</i>)</td>')
            $SelectThemes = @()
            foreach ( $Theme in $AvailableThemes | Sort -Unique ) {
                if ( $Theme -eq $ScriptVariables.Theme ) { $Selected = 'Selected' } else { $Selected = $null }
                $SelectThemes += '<option value="' + $Theme + '" ' + $Selected + '>' + ($Theme -replace '_',' ' -replace 'theme-','') + '</option>'
            }
            [void]$HTML.AppendLine('<td style="width: 50%;" align="right"><select class="selLang" name="Theme"/>' + $SelectThemes -join '' + '</select></td></tr>')
        }
        elseif ( $Setting.Name -eq 'AllowPersonalLinks' ) {
            if ( $ScriptVariables.AllowPersonalLinks -eq $true ) {
                $Enabled = 'checked'
            }
            else {
                $Enabled = $null
            }
            [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left">' + $Setting.Name + '</td><td align="right"><label class="switch"><input type=checkbox id="chkAllowPersonalLinks" name="AllowPersonalLinks" value="True" ' + $Enabled + '><span class="slider"></span></label></td></tr>')
        }
        elseif ( $Setting.Name -eq 'AllowPersonalTheme' ) {
            if ( $ScriptVariables.AllowPersonalTheme -eq $true ) {
                $Enabled = 'checked'
            }
            else {
                $Enabled = $null
            }
            [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left">' + $Setting.Name + '</td><td align="right"><label class="switch"><input type=checkbox id="chkAllowPersonalTheme" name="AllowPersonalTheme" value="True" ' + $Enabled + '><span class="slider"></span></label></td></tr>')
        }
        elseif ( $Setting.Name -eq 'ShowFooter' ) {
            if ( $ScriptVariables.ShowFooter -eq $true ) {
                $Enabled = 'checked'
            }
            else {
                $Enabled = $null
            }
            [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left">' + $Setting.Name + '</td><td align="right"><label class="switch"><input type=checkbox id="chkShowFooter" name="ShowFooter" value="True" ' + $Enabled + '><span class="slider"></span></label></td></tr>')
        }
        else {
            [void]$HTML.AppendLine('<tr><td style="width: 50%;" align="left"><label>' + $Setting.Name + '</label></td><td style="width: 50%;" align="right"><input type="text" value="' + $Setting.Value + '" disabled/></td></tr>')
        }
    }
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table with="100%" align="center" data-name="mytable" id="filteredTable" class="hover innerTable">')
    [void]$HTML.AppendLine('<tr><td align="left"><label style="vertical-align: top;">' + $ScriptVariables.Text.LblChooseLogo + '</label></td><td align="right"><input type="button" id="btnChooseLogo" style="align: right;" class="btn" value="' + $ScriptVariables.Text.UploadLogoBtn + '"/></td></tr>')
    [void]$HTML.AppendLine('</table>')
    [void]$HTML.AppendLine('</td></tr>')
    [void]$HTML.AppendLine('<tr><td align="right"><input type="text" id="base64area" name="Logo" placeholder="' + $ScriptVariables.Text.PhdUploadLogo + '" hidden/><img id="tempLogo" src="data:image/png;base64, ' + $ScriptVariables.Logo + '" height="75em" /></td></tr>')
    [void]$HTML.AppendLine('<input type="file" id="filLogo" accept=".jpg,.gif,.png,.svg" hidden/>')
    [void]$HTML.AppendLine('</form>')
    [void]$HTML.AppendLine('<form id="frmResetLogo" action="/ManageLink?ResetLogo" method="POST" enctype="multipart/form-data" accept-charset="' + $ScriptVariables.Charset + '"/>')
    [void]$HTML.AppendLine('<tr><td>')
    [void]$HTML.AppendLine('<table class="innerTable">')
    [void]$HTML.AppendLine('<tr><td align="left"><button class="btn reset" form="frmResetLogo" type="Submit">' + $ScriptVariables.Text.ResetLogo + '</button></td><td align="right"><input class="btn" id="SubmitBtn" form="frmUpdateSettings" type="Submit" value="' + $ScriptVariables.Text.SaveBtn + '"></td></tr>')
    [void]$HTML.AppendLine('</table>')
}
else { exit }
[void]$HTML.AppendLine( @"
      </table>
    </td></tr>
  </table>
  $( if ( $ScriptVariables.ShowFooter -eq $true ) { '<img width="50em" style="vertical-align: middle;" src="data:image/png;base64, ' + $(Get-Content ($ScriptVariables.ScriptPath + 'images\linx_base64.txt')) + '"/><pre style="vertical-align: middle;"> version ' + $($ScriptVariables.Version) + '</pre>' })
  <script src="/admin.js" type="text/javascript" nonce="{{nonce}}"></script>
  <script src="/scripts.js" type="text/javascript" nonce="{{nonce}}"></script>
</body>
</html>
"@ )
$HTML.ToString()