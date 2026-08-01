$global:ScriptVariables = @{ ScriptPath = ([regex]::match($PSCommandPath,".*(?:\\)")).Value }
if ( !$ScriptVariables.ScriptPath ) { $ScriptVariables.ScriptPath = $PSScriptRoot }
if ( $psISE    ) { $ScriptVariables.ScriptPath = ([regex]::match($psISE.CurrentFile.FullPath,".*(?:\\)")).Value   }
if ( $psEditor ) { $ScriptVariables.ScriptPath = Split-Path -Parent $psEditor.GetEditorContext().CurrentFile.Path }
if ( !$ScriptVariables.ScriptPath ) {
    if ( Test-path 'C:\RestPS\Linx\' ) { $ScriptVariables.ScriptPath = 'C:\RestPS\Linx\' }
    else { $ScriptVariables.ScriptPath = '\\webdiv-p101w\c$\RestPS\Linx\' }
}
import-module (Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'modules\Internal-CmdLets.psd1') -force

$RestPSparams = @{
            RestPSLocalRoot  = $ScriptVariables.ScriptPath
            RoutesFilePath   = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath 'endpoints\Routes.json'
            LogFile          = $ScriptVariables.LogRestPSPath
            LogLevel         = 'Info'
            Port             = $ScriptVariables.Port
        }

Start-RestPSListener @RestPSparams