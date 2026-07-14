# version 1.0.0 - 2022-03-05
# version 1.0.1 - 2025-03-19 - Added milliseconds to Write-Message timestamp
# version 1.0.2 - 2025-11-20 - Added support for compressed response

function Invoke-GetBody {
    if ($script:Request.HasEntityBody) {
        $script:RawBody = $script:Request.InputStream
        $Reader = New-Object System.IO.StreamReader @($script:RawBody, [System.Text.Encoding]::UTF8)
        $script:Body = $Reader.ReadToEnd()
        $Reader.close()
        $script:Body
    }
    else {
        $script:Body = "null"
        $script:Body
    }
}
function Invoke-GetContext {
    $script:context = $listener.GetContext()
    $Request = $script:context.Request
    $Request
}
function Invoke-RequestRouter {
    [CmdletBinding()]
    [OutputType([boolean])]
    [OutputType([Hashtable])]
    param(
        [Parameter(Mandatory = $true)][String]$RequestType,
        [Parameter(Mandatory = $true)][String]$RequestURL,
        [Parameter(Mandatory = $false)][String]$RequestArgs,
        [Parameter()][String]$RoutesFilePath
    )
    # Import Routes each pass, to include new routes.
    if (Test-Path -Path $RoutesFilePath) { $script:Routes = Get-Content -Raw $RoutesFilePath | ConvertFrom-Json }
    else { Throw "Import-RouteSet - Could not validate Path $RoutesFilePath" }
    $Route = ($Routes | Where-Object {$_.RequestType -eq $RequestType -and $_.RequestURL -eq $RequestURL})
    if ($null -ne $Route) {
        # Process Request
        $RequestCommand = Join-Path -Path $ScriptVariables.ScriptPath -ChildPath "endPoints\$($Route.RequestCommand)"

        # SECURITY: Validate that RequestCommand is either a .ps1 script or allowed static file
        $allowedExtensions = @('.ps1', '.css', '.js', '.jquery', '.ttf', '.eot', '.woff', '.woff2', '.html', '.htm', '.json', '.xml', '.txt')
        $commandExtension = [System.IO.Path]::GetExtension($RequestCommand).ToLower()

        if ($commandExtension -notin $allowedExtensions) {
            Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType ERROR -Message "Invoke-RequestRouter: Route command '$($Route.RequestCommand)' has invalid extension '$commandExtension'. Only .ps1 scripts and static files allowed."
            $script:StatusDescription = "Internal Server Error"
            $script:StatusCode = 500
            $script:result = $null
            return $null
        }

        set-location $PSScriptRoot
        if ($RequestCommand -match "\.ps1$") {
            # Execute Endpoint Script
            $CommandReturn = . $RequestCommand -RequestArgs $RequestArgs -Body $script:Body
        }
        elseif ( $RequestCommand -match "(.css|.js|.jquery|.ttf|.eot|.woff|.woff2)$" ) {
            $CommandReturn = Get-Content $RequestCommand -Raw
        }
        else {
            # SECURITY FIX: Removed Invoke-Expression to prevent command injection
            # All route commands must now be .ps1 scripts or static files
            Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType ERROR -Message "Invoke-RequestRouter: Route command '$RequestCommand' is not a .ps1 script or static file. Direct command execution is disabled for security."
            $script:StatusDescription = "Internal Server Error"
            $script:StatusCode = 500
            $CommandReturn = $null
        }

        if ($null -eq $CommandReturn) {
            # Not a valid response
            $script:StatusDescription = "Bad Request"
            $script:StatusCode = 400
        }
        else {
            # Valid response
            $script:result = $CommandReturn
            $script:StatusDescription = "OK"
            $script:StatusCode = 200
        }
    }
    else {
        # No matching Routes
        $script:StatusDescription = "Not Found"
        $script:StatusCode = 404
    }
    $script:result
}
function Invoke-StartListener {
    param(
        [Parameter(Mandatory = $true)][String]$Port,
        [Parameter()][String]$SSLThumbprint,
        [Parameter()][String]$SSLFriendlyName
    )
    if ($SSLThumbprint -or $SSLFriendlyName) {
        if ( $SSLThumbprint ) {
            # Verify the Certificate with the Specified Thumbprint is available.
            $CertificateListCount = ((Get-ChildItem -Path Cert:\LocalMachine -Recurse | Where-Object {$_.Thumbprint -eq "$SSLThumbprint"}) | Measure-Object).Count
        }
        if ( $SSLFriendlyName -and $null -eq $CertificateListCount ) {
            # Verify the Certificate with the Specified Thumbprint is available.
            $CertificateListCount = (((Get-ChildItem -Path Cert:\LocalMachine -Recurse) | Where-Object {$_.FriendlyName -match "^$SSLFriendlyName"}) | Select NotAfter | Sort NotAfter -Descending | Select -First 1 | Measure-Object).Count
        }
        if ($CertificateListCount -ne 0) { $Prefix = "https://" }
        else { Throw "Invoke-StartListener: Could not find Matching Certificate in CertStore: Cert:\LocalMachine" }
    }
    else {
        # No SSL Thumbprint present
        Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Invoke-StartListener: No SSL Thumbprint or matching SSL FriendlyName present"
        $Prefix = "http://"
    }

    try {
        $listener.Prefixes.Add("$($Prefix)$($ScriptVariables.ShortURL):$Port/")
        $listener.Start()
        $Host.UI.RawUI.WindowTitle = "RestPS - $Prefix - Port: $Port"
        Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType INFO -Message "Invoke-StartListener: Starting: $Prefix Listener on Port: $Port"
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Throw "Invoke-StartListener: $ErrorMessage $FailedItem"
    }
}
function Invoke-StreamOutput {
    $script:Response = $script:context.Response

    $rawPath = $script:context.Request.Url.AbsolutePath
    $extension = [System.IO.Path]::GetExtension($rawPath).ToLower()
    $staticExtensions = @('.js', '.css', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.woff', '.woff2', '.ttf', '.svg', '.json')

    if ( $extension -eq '.css') { $script:Response.ContentType = 'text/css' }
    elseif ($extension -eq '.js') { $script:Response.ContentType = 'application/javascript' }
    elseif ($extension -eq '.json') { $script:Response.ContentType = 'application/json' }
    elseif ($extension -in @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg')) { 
        $type = $extension.Replace('.','')
        if ($type -eq 'jpg') { $type = 'jpeg' }
        if ($type -eq 'svg') { $type = 'svg+xml' }
        $script:Response.ContentType = "image/$type" 
    }
    else { $script:Response.ContentType = 'text/html' }

    if ($extension -notin $staticExtensions) {
        $nonceHeader = $script:context.Request.Headers["X-CSP-Nonce"]
        if ($null -ne $nonceHeader -and $null -ne $script:result -and $script:result -is [string]) {
            $script:result = $script:result.Replace("{{nonce}}", $nonceHeader)
        }
    }

    $script:Response.StatusCode = $script:StatusCode
    $script:Response.StatusDescription = $script:StatusDescription
    
    $message = $script:result  
    [byte[]]$buffer = [System.Text.Encoding]::UTF8.GetBytes("$message")
    $script:Response.ContentLength64 = $buffer.length
    $script:Response.OutputStream.Write($buffer, 0, $buffer.length)
    $script:Response.Close()
}
function Start-RestPSListener {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = "Low"
    )]
    [OutputType([boolean])]
    [OutputType([Hashtable])]
    [OutputType([String])]
    param(
        [Parameter()][String]$RoutesFilePath = "$env:SystemDrive/RestPS/endpoints/RestPSRoutes.json",
        [Parameter()][String]$RestPSLocalRoot = "$env:SystemDrive/RestPS",
        [Parameter()][String]$Port = 8080,
        [Parameter()][String]$SSLThumbprint,
        [Parameter()][String]$SSLFriendlyName,
        [Parameter()][String]$Logfile = "$env:SystemDrive/RestPS/RestPS.log",
        [ValidateSet("ALL", "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "CONSOLEONLY", "OFF")]
        [Parameter()][String]$LogLevel = "INFO"
    )
    # Set a few Flags
    $script:Status = $true
    $script:ValidateClient = $true
    if ($pscmdlet.ShouldProcess("Starting .Net.HttpListener.")) {
        $script:listener = New-Object System.Net.HttpListener
        $listener.AuthenticationSchemes = 'Anonymous'
        $listener.UnsafeConnectionNtlmAuthentication = $true
        $listener.IgnoreWriteExceptions = $true

        Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Calling Invoke-StartListener"
        if ( $SSLThumbprint ) {
            Invoke-StartListener -Port $Port -SSLThumbPrint $SSLThumbprint
        }
        elseif ( $SSLFriendlyName ) {
            Invoke-StartListener -Port $Port -SSLFriendlyName $SSLFriendlyName
        }
        else {
            Invoke-StartListener -Port $Port
        }
        Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Finished Calling Invoke-StartListener"
        # Run until you send a GET request to /shutdown
        Do {
            # Capture requests as they come in (not Asyncronous)
            # Routes can be configured to be Asyncronous in Nature.
            Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Captured incoming request"
            $script:Request = Invoke-GetContext
            $script:ProcessRequest = $true
            $script:result = $null

            # Determine if a Body was sent with the Client request
            Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Executing Invoke-GetBody"
            $script:Body = Invoke-GetBody

            # Request Handler Data
            Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Determining Method and URL"
            $RequestType = $script:Request.HttpMethod
            $RawRequestURL = $script:Request.RawUrl
            Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType INFO -Message "Start-RestPSListener: New Request - User: $($context.User.Identity.Name -replace ("$($ScriptVariables.Domain)\\",'')) Method: $RequestType URL: $RawRequestURL"
            # Specific args will need to be parsed in the Route commands/scripts
            $RequestURL, $RequestArgs = $RawRequestURL.split("?")

            if ($script:ProcessRequest -eq $true) {
                # Break from loop if GET request sent to /shutdown
                Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Processing Request, Checking for Shutdown Command"
                if ($RequestURL -match '/EndPoint/Shutdown$') {
                    Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Shutting down RestEndpoint"
                    $script:result = "Shutting down RESTPS Endpoint."
                    $script:Status = $false
                    $script:StatusCode = 200
                }
                else {
                    # Attempt to process the Request.
                    Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType INFO -Message "Start-RestPSListener: Processing RequestType: $RequestType URL: $RequestURL Args: $RequestArgs"
                    $global:Nonce  = "$((New-Guid).guid)$((New-Guid).guid)" -replace '-',''
                    $script:result = Invoke-RequestRouter -RequestType "$RequestType" -RequestURL "$RequestURL" -RoutesFilePath "$RoutesFilePath" -RequestArgs "$RequestArgs"
                    Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType INFO -Message "Start-RestPSListener: Finished request. StatusCode: $script:StatusCode StatusDesc: $Script:StatusDescription"
                }
            }
            else {
                Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType INFO -Message "Start-RestPSListener: Unauthorized (401) NOT Processing RequestType: $RequestType URL: $RequestURL Args: $RequestArgs"
                $script:StatusDescription = "Unauthorized"
                $script:StatusCode = 401
            }
            # Stream the output back to requestor.
            Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Streaming response back to requestor."
            if ( $RequestURL -match "^/api/.*" ) { Invoke-StreamOutput -SendAsJSON }
            elseif ( $RequestURL -match "\.css$" ) { Invoke-StreamOutput -SendAsCSS }
            elseif ( $RequestURL -match "\.js$" ) { Invoke-StreamOutput -SendAsJavascript }
            elseif ( $RequestURL -match "\.ttf$" ) { Invoke-StreamOutput -SendAsFontTtf }
            elseif ( $RequestURL -match "\.otf$" ) { Invoke-StreamOutput -SendAsFontOtf }
            elseif ( $RequestURL -match "\.woff$" ) { Invoke-StreamOutput -SendAsFontWoff }
            elseif ( $RequestURL -match "\.woff2$" ) { Invoke-StreamOutput -SendAsFontWoff2 }
            else { Invoke-StreamOutput }
            Write-Log -LogFile $Logfile -LogLevel $logLevel -MsgType TRACE -Message "Start-RestPSListener: Streaming response is complete."
        } while ($script:Status -eq $true)
    }
    else { return $false }
}
function Compare-Weekday {
    [CmdletBinding()]
    [OutputType([boolean])]
    param( $Weekday = $null )
    
    if ($null -eq $Weekday) { return $false }
    else {
        $CurrentDay = (Get-Date).DayOfWeek
        if ($CurrentDay -eq $Weekday) { $true }
        else { $false }
    }
}
function Write-Message {
    [CmdletBinding(DefaultParameterSetName = 'LogFileFalse')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'LogFileTrue')]
        [Parameter(Mandatory = $true, ParameterSetName = 'LogFileFalse')]
        [string]$Message,
        [Parameter(Mandatory = $true, ParameterSetName = 'LogFileTrue')]
        [string]$Logfile,
        [Parameter(Mandatory = $false, ParameterSetName = 'LogFileTrue')]
        [Parameter(Mandatory = $true, ParameterSetName = 'LogFileFalse')]
        [validateset('ConsoleOnly', 'Both', 'noConsole','None', IgnoreCase = $true)]
        [string]$OutputStyle
    )
    
    try {
        $dateNow = $(get-date).ToString("yyyy-MM-dd HH:mm:ss")
        switch ($OutputStyle) {
            ConsoleOnly {
                Write-Output ""
                Write-Output "$dateNow $Message"
            }
            None {}
            Both {
                Write-Output ""
                Write-Output "$dateNow $Message"
                if (!(Test-Path $logfile -ErrorAction SilentlyContinue)) {
                    Write-Warning "Logfile does not exist."
                    New-Log -Logfile $Logfile
                }
                Write-Output "$dateNow $Message" | Out-File $Logfile -append -encoding utf8
            }
            noConsole {
                if (!(Test-Path $logfile -ErrorAction SilentlyContinue)) {
                    Write-Warning "Logfile does not exist."
                    New-Log -Logfile $Logfile
                }
                Write-Output "$dateNow $Message" | Out-File $Logfile -append -encoding utf8
            }
            default {
                Write-Output ""
                Write-Output "$dateNow $Message"
                if (!(Test-Path $logfile -ErrorAction SilentlyContinue)) {
                    Write-Warning "Logfile does not exist."
                    New-Log -Logfile $Logfile
                }
                Write-Output "$dateNow $Message" | Out-File $Logfile -append -encoding utf8
            }
        }
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Throw "Write-Message: $ErrorMessage $FailedItem"
    }
}
function Invoke-RollLog {
    [CmdletBinding()]
    [OutputType([boolean])]
    param(
        [Parameter(Mandatory = $true)][string]$Logfile,
        [Parameter(Mandatory = $true)][string]$Weekday

    )

    try {
        if (!(Test-Path -Path $Logfile)) {
            Write-Message -Message "#################### New Log created #####################" -Logfile $logfile -OutputStyle both
            Throw "LogFile path: $Logfile does not exist."
        }
        else {
            if (Compare-Weekday -Weekday $Script:Weekday) { return $true }
            else {
                $CurrentTime = Get-Date -Format MMddHHmm
                $OldLogName = "$currentTime.log"
                Rename-Item -Path $logfile -NewName $OldLogName -Force -Confirm:$false
                Write-Message -Message "#################### New Log created #####################" -Logfile $logfile
            }
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Throw "Invoke-RollLog: $ErrorMessage $FailedItem"
    }
}
function New-Log {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param( [Parameter(Mandatory = $true)][string]$Logfile )
    
    try {
        if ( !(Split-Path -Path $Logfile -ErrorAction SilentlyContinue)) {
            Write-Message -Message "Creating new Directory." -OutputStyle consoleOnly
            if ($PSCmdlet.ShouldProcess("Creating new Directory")) {New-Item (Split-Path -Path $Logfile) -ItemType Directory -Force}
        }
        Write-Message -Message "Creating new file." -OutputStyle consoleOnly
        if ($PSCmdlet.ShouldProcess("Creating new File")) {New-Item $logfile -type file -force -value "New file created."}
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Throw "New-Log: $ErrorMessage $FailedItem"
    }
}
function Write-Log {
    [CmdletBinding(DefaultParameterSetName = 'LogFileFalse')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'LogFileTrue')]
        [Parameter(Mandatory = $true, ParameterSetName = 'LogFileFalse')]
        [string]$Message,
        [Parameter(Mandatory = $true, ParameterSetName = 'LogFileTrue')]
        [string]$Logfile = $global:Logfile,
        [Parameter(ParameterSetName = 'LogFileTrue')]
        [Parameter(ParameterSetName = 'LogFileFalse')]
        [ValidateSet("ALL", "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "CONSOLEONLY", "OFF")]
        [string]$LogLevel = "INFO",
        [Parameter(ParameterSetName = 'LogFileTrue')]
        [Parameter(ParameterSetName = 'LogFileFalse')]
        [ValidateSet("TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "CONSOLEONLY")]
        [string]$MsgType = "INFO"
    )

    try {
        $Message = $MsgType + ": " + $Message
        if (($Logfile -eq "") -or ($null -eq $logfile)) { Write-Message -Message $Message -OutputStyle $OutPutStyle }
        else { Write-Message -Message $Message -Logfile $Logfile -OutputStyle noConsole }
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Throw "Write-Log: $ErrorMessage $FailedItem"
    }
}
function Start-SQLCommand {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$false)][string]$SQLServer = $SQLValues.SQLServer,
        [parameter(Mandatory=$false)][string]$Database = $SQLValues.DataBase,
        [parameter(Mandatory=$true)][string]$SQLQuery
    )

    try{
    	$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    	#$SqlConnection.ConnectionString = "Server=$SQLServer;Database=$Database;Integrated Security=True;"
        $SqlConnection.ConnectionString = "Server=$SQLServer;Database=$Database;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"
    	$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    	$SqlCmd.CommandText = $SQLQuery
    	$SqlCmd.Connection = $SqlConnection
    	$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    	$SqlAdapter.SelectCommand = $SqlCmd
    	$DataSet = New-Object System.Data.DataSet
    	$nSet = $SqlAdapter.Fill($DataSet)
    	$OutputTable = $DataSet.Tables[0]
    	$SqlConnection.Close();
    	Return $OutputTable
    }
    catch{ Write-Warning $_.Exception.Message }
}
function Invoke-SQLCommand {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$false)][string]$SQLServer = $ScriptVariables.SQLServer,
        [Parameter(Mandatory=$false)][string]$Database = $ScriptVariables.Database,
        [Parameter(Mandatory=$true)][string]$Command
    )
    Invoke-SqlCmd -ServerInstance $SQLServer -Database $Database -Query $Command -TrustServerCertificate -MultiSubnetFailover
}