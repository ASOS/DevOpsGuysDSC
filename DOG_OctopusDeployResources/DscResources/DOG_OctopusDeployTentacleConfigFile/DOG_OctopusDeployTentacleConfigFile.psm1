# TODO:  Both Role and Environment may be able to accept multiple values when calling Tentacle.exe, so we could make those properties
#        string arrays on the DSC resources as well.  According to the comments posted at
#        http://docs.octopusdeploy.com/display/OD/Automating+Tentacle+installation , the proper syntax for specifying multiple roles
#        is to use the --role parameter multiple times (not comma-separated or anything like that.)  The same may be true for
#        --environment; requires testing. (Role has been updated, environment still outstanding)

# TODO:  Do we need to support a Listening tentacle that trusts multiple Octopus Deploy servers?  ServerThumbprint could be made an array
#        property, and the underlying code updated to support this.


. "$PSScriptRoot\..\..\OctopusCommon.ps1"

function Get-TargetResource
{
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [string] $HomeDirectory,

        [Parameter(Mandatory)]
        [string] $TentacleName
    )

    $configuration = @{
        HomeDirectory         = $HomeDirectory
        TentacleName          = $TentacleName
        Ensure                = 'Absent'
        DeploymentDirectory   = $null
        Port                  = $null
        CommunicationMode     = $null
        ServerName            = $null
        ServerThumbprint      = $null
        ServerSQUID           = $null
        ServerPort            = $null
        SQUID                 = $null
        CertificateThumbprint = $null
    }

    $path = Get-TentacleConfigPath -RootPath $HomeDirectory -TentacleName $TentacleName

    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $configFile = Import-TentacleConfigFile -Path $path

        $configuration['Ensure']                = 'Present'
        $configuration['DeploymentDirectory']   = $configFile.DeploymentDirectory
        $configuration['Port']                  = $configFile.PortNumber
        $configuration['CertificateThumbprint'] = $configFile.CertificateThumbprint
        $configuration['SQUID']                 = $configFile.SQUID

        # Should the DSC resource support multiple trusted servers?  For now, we're assuming one, which is a little bit ugly.
        $server = $configFile.TrustedServers | Select-Object -First 1

        if ($server)
        {
            $configuration['CommunicationMode'] = if ($server.CommunicationStyle -eq 'TentaclePassive') { 'Listen' } else { 'Poll' }
            $configuration['ServerSQUID']       = $server.Squid
            $configuration['ServerThumbprint']  = $server.Thumbprint

            if (($uri = $server.Address -as [uri]))
            {
                $configuration['ServerName'] = $uri.Host
                $configuration['ServerPort'] = $uri.Port
            }
        }
    }

    return $configuration
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [string] $HomeDirectory,

        [Parameter(Mandatory)]
        [string] $TentacleName,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $ServerName,

        [string] $ServerThumbprint,

        [ValidateNotNullOrEmpty()]
        [string] $DeploymentDirectory = 'C:\Octopus\Applications',

        [uint16] $Port = 10933,

        [ValidateSet('Listen', 'Poll')]
        [string] $CommunicationMode = 'Listen',

        [pscredential] $RegistrationCredential,

        [string[]] $Role,

        [string] $Environment,

        [uint16] $ServerPort = 10943,

        [string] $ServerScheme = "http",

        [string] $ApiKey
    )

    Assert-ValidParameterCombinations @PSBoundParameters

    $tentacleExe = Get-TentacleExecutablePath
    $tentacleVersion = Get-TentacleVersion -TentacleExePath $tentacleExe
    $path = Get-TentacleConfigPath -RootPath $HomeDirectory -TentacleName $TentacleName -OctopusVersion $tentacleVersion

    $fileExists = Test-Path -LiteralPath $path -PathType Leaf
    $serviceName = Get-TentacleServiceName -TentacleName $TentacleName

    switch ($Ensure)
    {
        'Present'
        {
            $doRestartService = $false
            $service = Get-Service -Name $serviceName -ErrorAction Ignore

            if ($null -ne $service -and $service.CanStop)
            {
                Write-Verbose "Stopping tentacle service '$serviceName' before modifying the config file."

                try
                {
                    Stop-Service -InputObject $service -ErrorAction Stop
                    $doRestartService = $true
                }
                catch
                {
                    Write-Error -ErrorRecord $_
                    return
                }
            }

            if (-not $fileExists)
            {
                New-TentacleInstance -TentacleExePath $tentacleExe -InstanceName $TentacleName -Path $path
            }

            $configFile = Import-TentacleConfigFile -Path $path

            # Should the DSC resource support multiple trusted servers?  For now, we're assuming one, which is a little bit ugly.
            $server = $configFile.TrustedServers | Select-Object -First 1
            $mode = if ($server.CommunicationStyle -eq 'TentaclePassive') { 'Listen' } else { 'Poll' }

            if ([string]::IsNullOrEmpty($configFile.SQUID) -and $tentacleVersion.Major -lt 3)
            {
                New-TentacleSquid -TentacleExePath $tentacleExe -InstanceName $TentacleName
            }

            if ([string]::IsNullOrEmpty($configFile.Certificate))
            {
                New-TentacleCertificate -TentacleExePath $tentacleExe -InstanceName $TentacleName
            }

            if ($configFile.HomeDirectory -ne $HomeDirectory)
            {
                Set-TentacleHomeDirectory -TentacleExePath $tentacleExe -InstanceName $TentacleName -HomeDirectory $HomeDirectory
            }

            if ($configFile.DeploymentDirectory -ne $DeploymentDirectory)
            {
                Set-TentacleDeploymentDirectory -TentacleExePath $tentacleExe -InstanceName $TentacleName -DeploymentDirectory $DeploymentDirectory
            }

            if ($configFile.PortNumber -ne $Port)
            {
                Set-TentaclePort -TentacleExePath $tentacleExe -InstanceName $TentacleName -Port $Port
            }

            # from current configuration
            $uri = $server.Address -as [uri]

            # from desired configuration
            $serverUrl = [uri]("{0}://{1}" -f $ServerScheme, $ServerName)
            $matchUrl = [uri]("{0}://{1}:{2}" -f $ServerScheme, $ServerName, $ServerPort)

            switch ($CommunicationMode)
            {
                'Listen'
                {
                    if ($server.Thumbprint -ne $ServerThumbprint -or
                        $uri -ne $matchUrl -or
                        $server.CommunicationStyle -ne 'TentaclePassive')
                    {
                        Set-TentacleListener -TentacleExePath $tentacleExe `
                                             -InstanceName $TentacleName `
                                             -ServerUrl $serverUrl `
                                             -ServerThumbprint $ServerThumbprint `
                                             -ApiKey $ApiKey `
                                             -Environment $Environment `
                                             -Role $Role
                    }
                }

                'Poll'
                {
                    if ($uri.Scheme -ne $ServerScheme -or
                        $uri.Host -ne $ServerName -or
                        $uri.Port -ne $ServerPort -or
                        $server.CommunicationStyle -ne 'TentacleActive')
                    {

                        Register-PollingTentacle -TentacleExePath $tentacleExe `
                                                 -InstanceName    $TentacleName `
                                                 -ServerUrl       $serverUrl `
                                                 -Environment     $Environment `
                                                 -Credential      $RegistrationCredential `
                                                 -ServerPort      $ServerPort `
                                                 -Role            $Role
                    }
                }
            }

            if ($doRestartService)
            {
                Write-Verbose "Config file modifications complete.  Restarting tentacle service '$serviceName'."
                Start-Service -InputObject $service
            }
        }

        'Absent'
        {
            if ($fileExists)
            {
                Write-Verbose "Configuration file '$path' exists and Ensure is set to Absent.  Deleting file."
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
        }
    }

}

function Test-TargetResource
{
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string] $HomeDirectory,

        [Parameter(Mandatory)]
        [string] $TentacleName,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $ServerName,

        [string] $ServerThumbprint,

        [ValidateNotNullOrEmpty()]
        [string] $DeploymentDirectory = 'C:\Octopus\Applications',

        [uint16] $Port = 10933,

        [ValidateSet('Listen', 'Poll')]
        [string] $CommunicationMode = 'Listen',

        [pscredential] $RegistrationCredential,

        [string[]] $Role,

        [string] $Environment,

        [uint16] $ServerPort = 10943,

        [string] $ServerScheme = "http",

        [string] $ApiKey
    )

    Assert-ValidParameterCombinations @PSBoundParameters

    try
    {
        $tentacleExe = Get-TentacleExecutablePath
        $tentacleVersion = Get-TentacleVersion -TentacleExePath $tentacleExe
    }
    catch
    {
        $tentacleVersion = [version]'0.0'
    }

    $path = Get-TentacleConfigPath -RootPath $HomeDirectory -TentacleName $TentacleName -OctopusVersion $tentacleVersion
    $fileExists = Test-Path -LiteralPath $path -PathType Leaf

    switch ($Ensure)
    {
        'Present'
        {
            if (-not $fileExists) { return $false }

            $configFile = Import-TentacleConfigFile -Path $path

            # Should the DSC resource support multiple trusted servers?  For now, we're assuming one, which is a little bit ugly.
            $server = $configFile.TrustedServers | Select-Object -First 1
            $mode = if ($server.CommunicationStyle -eq 'TentaclePassive') { 'Listen' } else { 'Poll' }

            if ($configFile.HomeDirectory       -ne $HomeDirectory -or
                $configFile.DeploymentDirectory -ne $DeploymentDirectory -or
                $configFile.PortNumber          -ne $Port -or
                $mode                           -ne $CommunicationMode -or
                [string]::IsNullOrEmpty($configFile.CertificateThumbprint))
            {
                return $false
            }

            if ($tentacleVersion.Major -lt 3 -and [string]::IsNullOrEmpty($configFile.SQUID))
            {
                return $false
            }

            if ($CommunicationMode -eq 'Listen')
            {
                if ($server.Thumbprint -ne $ServerThumbprint)
                {
                    return $false
                }
            }
            else
            {
                $uri = $server.Address -as [uri]
                if ($uri.Host -ne $ServerName -or $uri.Port -ne $ServerPort)
                {
                    return $false
                }
            }

            return $true
        }

        'Absent'
        {
            return -not $fileExists
        }
    }
}

function Assert-ValidParameterCombinations
{
    param (
        [Parameter(Mandatory)]
        [string] $HomeDirectory,

        [Parameter(Mandatory)]
        [string] $TentacleName,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $ServerName,

        [string] $ServerThumbprint,

        [ValidateNotNullOrEmpty()]
        [string] $DeploymentDirectory = 'C:\Octopus\Applications',

        [uint16] $Port = 10933,

        [ValidateSet('Listen', 'Poll')]
        [string] $CommunicationMode = 'Listen',

        [pscredential] $RegistrationCredential,

        [string[]] $Role,

        [string] $Environment,

        [uint16] $ServerPort = 10943,

        [string] $ServerScheme = "http",

        [string] $ApiKey
    )

    if ($CommunicationMode -eq 'Poll')
    {
        if ([string]::IsNullOrEmpty($Role) -or
            [string]::IsNullOrEmpty($Environment) -or
            [string]::IsNullOrEmpty($ServerName) -or
            $null -eq $RegistrationCredential)
        {
            throw 'The ServerName, Role, Environment, and RegistrationCredential parameters are required when CommunicationMode is set to Poll.'
        }
    }
    else
    {
        if ([string]::IsNullOrEmpty($ServerThumbprint))
        {
            throw 'The ServerThumbprint parameter is required when CommunicationMode is set to Listen.'
        }
    }
}

function Import-TentacleConfigFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    Write-Verbose "Importing tentacle configuration file from '$Path'"

    if (-not (Test-Path -LiteralPath $Path))
    {
        throw "Path '$Path' does not exist."
    }

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file -isnot [System.IO.FileInfo])
    {
        throw "Path '$Path' does not refer to a file."
    }

    $xml = New-Object xml
    try
    {
        $xml.Load($file.FullName)
    }
    catch
    {
        throw
    }

    try {
        # The extra set of parentheses here looks weird, but is necessary to work around a weird bug with ConvertFrom-Json and the array subexpression operator.
        # For some reason, this results in a nested array by default, which isn't supposed to happen.  The extra set of parens changes how PowerShell evaluates
        # the expression, and causes the array subexpression to work the way it's supposed to; a new array is only created if the result of the inner expression
        # is not already an array.

        $trustedServers = @((ConvertFrom-Json $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.Communication.TrustedOctopusServers"]/text()').Value))

        foreach ($server in $trustedServers)
        {
            if ($server.CommunicationStyle -eq '1')
            {
                $server.CommunicationStyle = 'TentaclePassive'
            }
            elseif ($server.CommunicationStyle -eq '2')
            {
                $server.CommunicationStyle = 'TentacleActive'
            }
        }
    } catch {
        $trustedServers = @()
    }

    return [pscustomobject] @{
        SQUID                 = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Communications.Squid"]/text()').Value
        HomeDirectory         = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Home"]/text()').Value
        MasterKey             = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Storage.MasterKey"]/text()').Value
        Certificate           = $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.Certificate"]/text()').Value
        CertificateThumbprint = $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.CertificateThumbprint"]/text()').Value
        DeploymentDirectory   = $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.Deployment.ApplicationDirectory"]/text()').Value
        PortNumber            = $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.Services.PortNumber"]/text()').Value -as [int]
        TrustedServers        = $trustedServers
    }
}

function New-TentacleInstance
{
    param ($TentacleExePath, $InstanceName, $Path)

    Write-Verbose "Creating new tentacle configuration file '$Path', instance '$InstanceName'"

    & $TentacleExePath --console create-instance --instance $InstanceName --config $Path

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when creating a new instance"
    }
}

function New-TentacleSquid
{
    param ($TentacleExePath, $InstanceName)

    Write-Verbose "Generating new SQUID for tentacle instance '$InstanceName'"

    & $TentacleExePath --console new-squid --instance $InstanceName

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when creating a new client SQUID"
    }
}

function New-TentacleCertificate
{
    param ($TentacleExePath, $InstanceName)

    Write-Verbose "Generating new client certificate for tentacle instance '$InstanceName'"

    & $TentacleExePath --console new-certificate --instance $InstanceName

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when creating a new client certificate"
    }
}

function Set-TentacleHomeDirectory
{
    param ($TentacleExePath, $InstanceName, $HomeDirectory)

    Write-Verbose "Setting tentacle instance '$InstanceName' home directory to '$HomeDirectory'"

    & $TentacleExePath --console configure --instance $InstanceName --home $HomeDirectory

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when configuring the tentacle Home Directory"
    }
}

function Set-TentacleDeploymentDirectory
{
    param ($TentacleExePath, $InstanceName, $DeploymentDirectory)

    Write-Verbose "Setting tentacle instance '$InstanceName' deployment directory to '$DeploymentDirectory'"

    & $TentacleExePath --console configure --instance $InstanceName --app $DeploymentDirectory

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when configuring the tentacle Deployment Directory"
    }
}

function Set-TentaclePort
{
    param ($TentacleExePath, $InstanceName, $Port)

    Write-Verbose "Setting tentacle instance '$InstanceName' client port to $Port"

    & $TentacleExePath --console configure --instance $InstanceName --port $Port

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when configuring the tentacle client port"
    }
}

function Set-TentacleListener
{
    param ($TentacleExePath, $InstanceName, $ServerUrl, $ServerThumbprint, $ApiKey, $Environment, $Role)

    Write-Verbose "Configuring listening tentacle, instance '$InstanceName', to trust Octopus Deploy server with thumbprint '$ServerThumbprint'"

    & $TentacleExePath --console configure --instance $InstanceName --reset-trust
    & $TentacleExePath --console configure --instance $InstanceName --trust $ServerThumbprint

    # Build up the command that will register the tentacle with the server
    $cmd_parts = New-Object System.Collections.ArrayList
    $cmd_parts.Add(("& '{0}'" -f $TentacleExePath)) | Out-Null
    $cmd_parts.Add("register-with") | Out-Null
    $cmd_parts.Add("--console") | Out-Null
    $cmd_parts.Add(('--instance "{0}"' -f $InstanceName)) | Out-Null
    $cmd_parts.Add(('--server "{0}"' -f $ServerUrl)) | Out-Null
    $cmd_parts.Add(('--environment "{0}"' -f $Environment)) | Out-Null
    $cmd_parts.Add(('--name {0}' -f $env:COMPUTERNAME)) | Out-Null
    $cmd_parts.Add('--comms-style TentaclePassive') | Out-Null
    $cmd_parts.Add(('--apiKey "{0}"' -f $ApiKey)) | Out-Null
    $cmd_parts.Add('--force') | Out-Null

    # Now add the roles to the command
    foreach ($r in $Role) {
      $cmd_parts.Add(('--role "{0}"' -f $r)) | Out-Null
    }

    # Build up the command to run
    $cmd = $cmd_parts -join " "

    Write-Verbose ("Registration Command: {0}" -f $cmd)

    # Run the command
    Invoke-Expression -Command $cmd

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when configuring the tentacle trusted server."
    }
}

function Register-PollingTentacle
{
    param ($TentacleExePath, $InstanceName, $ServerUrl, $Environment, $Credential, $ServerPort, $Role)

    Write-Verbose "Registering polling tentacle, instance '$InstanceName', with Octopus Deploy server ${ServerName}:${ServerPort}."

    $obj = [pscustomobject] @{
        Environment = $Environment
        Role        = $Role
        Username    = $Credential.UserName
    }

    Write-Debug "Registration settings: `r`n$($obj | Format-List | Out-String)"

    $ptr = $null
    try
    {
        $user = $Credential.UserName
        $ptr  = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Credential.Password)
        $pass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    }
    catch
    {
        throw
    }
    finally
    {
        if ($null -ne $ptr) { [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr); $ptr = $null }
    }

    & $TentacleExePath --console configure --instance $InstanceName --reset-trust

    # Create an array to hold all the options that need to be passed to the command
    # This is done so that all the roles are catered for
    $cmd_parts = New-Object System.Collections.ArrayList
    $cmd_parts.Add(("& '{0}'" -f $TentacleExePath)) | Out-Null
    $cmd_parts.Add("register-with") | Out-Null
    $cmd_parts.Add("--console") | Out-Null
    $cmd_parts.Add(('--instance "{0}"' -f $InstanceName)) | Out-Null
    $cmd_parts.Add(('--server "{0}"' -f $ServerUrl)) | Out-Null
    $cmd_parts.Add(('--environment "{0}"' -f $Environment)) | Out-Null
    $cmd_parts.Add(('--name {0}' -f $env:COMPUTERNAME)) | Out-Null
    $cmd_parts.Add(('--username {0}' -f $user)) | Out-Null
    $cmd_parts.Add(('--password {0}' -f $pass)) | Out-Null
    $cmd_parts.Add('--comms-style TentacleActive') | Out-Null
    $cmd_parts.Add(('--server-comms-port {0}' -f $ServerPort)) | Out-Null
    $cmd_parts.Add('--force') | Out-Null

    # Now add the roles to the command
    foreach ($r in $role) {
      $cmd_parts.Add(('--role "{0}"' -f $r)) | Out-Null
    }

    # Build up the command to run
    $cmd = $cmd_parts -join " "

    Write-Verbose ("Registration Command: {0}" -f $cmd)

    # Run the command
    Invoke-Expression -Command $cmd

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when registering with the server."
    }
}

Export-ModuleMember -Function Get-TargetResource,
                              Test-TargetResource,
                              Set-TargetResource

