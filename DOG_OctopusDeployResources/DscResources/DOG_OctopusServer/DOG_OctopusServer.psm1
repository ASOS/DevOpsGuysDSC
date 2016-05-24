function Get-TargetResource
{
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [string] $InstanceName,
        [Parameter(Mandatory)]
        [string] $ConfigFile
    )

    $configuration = @{
        ConfigFile                             = $ConfigFile
        Ensure                                 = 'Absent'
        CommsListenPort                        = $null
        HomePath                               = $null
        ServerNodeName                         = $null
        DBConnectionString                     = $null
        UpgradeCheck                           = $null
        UpgradeCheckStatistics                 = $null
        WebAuthenticationMode                  = $null
        WebForceSSL                            = $null
        WebListenPrefixes                      = $null
        InstanceName                           = $null
        ServiceAccount                         = $null
        ServiceStatus                          = $null
        AllowFormsAuthenticationForDomainUsers = $null
    }

    if (Test-Path -LiteralPath $ConfigFile -PathType Leaf)
    {
        $config = Import-ServerConfigFile -Path $ConfigFile

        $configuration['Ensure']                                 = 'Present'
        $configuration['CommsListenPort']                        = $config.OctopusCommunicationsServicesPort
        $configuration['HomePath']                               = $config.OctopusHome
        $configuration['ServerNodeName']                         = $config.OctopusServerNodeName
        $configuration['DBConnectionString']                     = $config.OctopusStorageExternalDatabaseConnectionString
        $configuration['UpgradeCheck']                           = $config.OctopusUpgradesAllowChecking
        $configuration['UpgradeCheckStatistics']                 = $config.OctopusUpgradesIncludeStatistics
        $configuration['WebAuthenticationMode']                  = $config.OctopusWebPortalAuthenticationMode
        $configuration['WebForceSSL']                            = $config.OctopusWebPortalForceSsl
        $configuration['WebListenPrefixes']                      = $config.OctopusWebPortalListenPrefixes
        $configuration['AllowFormsAuthenticationForDomainUsers'] = $config.OctopusWebPortalAllowFormsAuthenticationForDomainUsers
    }

    $service = Get-OctopusDeployService
    if ($null -ne $service) {
        $configuration['InstanceName']                           = $service.InstanceName
        $configuration['ServiceAccount']                         = $service.UserName
        $configuration['ServiceStatus']                          = $service.ServiceStatus
    }

    return $configuration
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [ValidateSet("Absent","Present")]
        [System.String]
        $Ensure,

        [System.String]
        $ConfigFile,

        [System.String]
        $HomePath,

        [System.String]
        $DBConnectionString,

        [System.Boolean]
        $UpgradeCheck,

        [System.Boolean]
        $UpgradeCheckStatistics,

        [System.String]
        $WebAuthenticationMode,

        [System.Boolean]
        $WebForceSSL,

        [System.String]
        $WebListenPrefixes,

        [System.String]
        $CommsListenPort,

        [System.String]
        $ServerNodeName = $env:COMPUTERNAME,

        [System.String]
        $AdminUser,

        [System.String]
        $AdminPassword,

        [System.String]
        $LicenceFile,

        [System.String]
        $ServiceAccount,

        [System.String]
        $ServicePassword,

        [System.String]
        $LogDir,

        [ValidateSet("Standalone","Leader","Follower")]
        [System.String]
        $HighAvailabilityMode,

        [System.String]
        $MasterKey,

        [System.Boolean]
        $AllowFormsAuthenticationForDomainUsers = $true
    )

    # Check that the licence file exists so that it can be base64 encoded
    if (Test-Path -Path $LicenceFile) {
        $licence = Get-Content -Path $LicenceFile -Raw
        $data = [System.Text.Encoding]::UTF8.GetBytes($licence)
        $encoded_licence = [System.Convert]::ToBase64String($data)
    } else {
        throw [System.IO.FileNotFoundException] "Licence file cannot be found: $LicenceFile"
    }

    if ((Test-Path -Path $LogDir) -eq $false) {
        New-Item -Type Directory -Path $LogDir | Out-null
    }

    # Determine the logfile to use
    $logfile = "{0}\Octopus.Server.Cmd.{1}.log" -f $logdir, (Get-Date -uformat "%Y%m%d-%H%M")
    Write-Verbose ("Configuration commands will be logged to: {0}" -f $logfile)

    # build up the configuration for the octopus server
    $cmd = '& "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" create-instance --console --instance "{0}" --config "{1}"' -f $InstanceName, $ConfigFile
    Invoke-AndAssert $cmd -LogFile $logfile

    # Build up the array of replacements int he cmd
    $substitutions = @(
        $InstanceName
        $HomePath
        $DBConnectionString
        $UpgradeCheck.ToString()
        $UpgradeCheckStatistics.ToString()
        $WebAuthenticationMode
        $WebForceSSL.ToString()
        $WebListenPrefixes
        $CommsListenPort
        $ServerNodeName
        $AllowFormsAuthenticationForDomainUsers
    )

    $cmd = @'
& "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" configure --console --instance "{0}" `
                        --home "{1}" `
                        --storageConnectionString "{2}" `
                        --upgradeCheck "{3}" `
                        --upgradeCheckWithStatistics "{4}" `
                        --webAuthenticationMode "{5}" `
                        --webForceSSL "{6}" `
                        --webListenPrefixes "{7}" `
                        --commsListenPort "{8}" `
                        --serverNodeName "{9}" `
                        --allowFormsAuthenticationForDomainUsers "{10}" `
'@ -f $substitutions

    if ($MasterKey -ne $null) {
        $cmd = "$cmd --MasterKey `"$MasterKey`""
    }

    Invoke-AndAssert $cmd -LogFile $logfile

    if ($HighAvailabilityMode -ne 'Follower') {
        $cmd = '& "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" database --console --instance "{0}" -create' -f $InstanceName
        Invoke-AndAssert $cmd  -LogFile $logfile
    }

    $cmd = '& "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" service --console --instance "{0}" --stop' -f $InstanceName
    Invoke-AndAssert $cmd -LogFile $logfile

    if ($HighAvailabilityMode -ne 'Follower') {
        if ($WebAuthenticationMode -eq 'Domain') {
            $cmd = '& "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" admin --console --instance "{0}" --username "{1}"' -f $InstanceName, $AdminUser
        } else {
            $cmd = '& "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" admin --console --instance "{0}" --username "{1}" --password "{2}"' -f $InstanceName, $AdminUser, $AdminPassword
        }
        Invoke-AndAssert $cmd -LogFile $logfile

        $cmd = '& "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" license --console --instance "{0}" --licenseBase64 "{1}"' -f $InstanceName, $encoded_licence
        Invoke-AndAssert $cmd -LogFile $logfile
    }

    if ($ServiceAccount -like ".\*") {
        #bit of a hacky workaround not being able to refer to env variables in the mof
        $ServiceAccount = $ServiceAccount.TrimStart('.\')
        $ServiceAccount = "$($env:computername)\$ServiceAccount"
    }

    $cmd = @'
& "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" service --console --instance "{0}" `
                      --install `
                      --reconfigure `
                      --start `
                      --username "{1}" `
                      --password "{2}"
'@ -f $InstanceName, $ServiceAccount, $ServicePassword

    Invoke-AndAssert $cmd -LogFile $logfile
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [ValidateSet("Absent","Present")]
        [System.String]
        $Ensure,

        [System.String]
        $ConfigFile,

        [System.String]
        $HomePath,

        [System.String]
        $DBConnectionString,

        [System.Boolean]
        $UpgradeCheck,

        [System.Boolean]
        $UpgradeCheckStatistics,

        [System.String]
        $WebAuthenticationMode,

        [System.Boolean]
        $WebForceSSL,

        [System.String]
        $WebListenPrefixes,

        [System.String]
        $CommsListenPort,

        [System.String]
        $ServerNodeName = $env:COMPUTERNAME,

        [System.String]
        $AdminUser,

        [System.String]
        $AdminPassword,

        [System.String]
        $LicenceFile,

        [System.String]
        $ServiceAccount,

        [System.String]
        $ServicePassword,

        [System.String]
        $LogDir,

        [ValidateSet("Standalone","Leader", "Follower")]
        [System.String]
        $HighAvailabilityMode,

        [System.String]
        $MasterKey,

        [System.Boolean]
        $AllowFormsAuthenticationForDomainUsers = $true
    )

    # set the default value of the test
    # This assumes that everything is all working correctly
    $test = $true

    $fileExists = Test-Path -LiteralPath $ConfigFile -PathType Leaf
    switch ($Ensure)
    {
        'Present'
        {
             if (-not $fileExists) { return $false }

            $config = Import-ServerConfigFile -Path $ConfigFile

            if ($config.OctopusHome -ne $HomePath) { return $false }
            if ($config.OctopusStorageExternalDatabaseConnectionString -ne $DBConnectionString) { return $false }
            if ($config.OctopusUpgradesAllowChecking -ne $UpgradeCheck) { return $false }
            if ($config.OctopusUpgradesIncludeStatistics -ne $UpgradeCheckStatistics) { return $false }
            if ($config.OctopusWebPortalAuthenticationMode -ne $WebAuthenticationMode) { return $false }
            if ($config.OctopusWebPortalForceSsl -ne $WebForceSSL) { return $false }
            if ($config.OctopusServerNodeName -ne $ServerNodeName) { return $false }
            if ($config.OctopusCommunicationsServicesPort -ne $CommsListenPort) { return $false }
            if ($config.OctopusWebPortalListenPrefixes -ne $WebListenPrefixes) { return $false }
            if ($config.OctopusWebPortalAllowFormsAuthenticationForDomainUsers -ne $AllowFormsAuthenticationForDomainUsers) { return $false }

            $service = Get-OctopusDeployService
            if ($service.InstanceName -ne $InstanceName) { return $false }
            if ($service.UserName -ne $ServiceAccount) { return $false }
            if ($service.ServiceStatus -ne 'Running') { return $false }

            # cant retrieve the current admin creds, so cant check... Should we try and login with them?
            # AdminUser 
            # AdminPassword

            # cant retreive a service password... ServiceStatus=Running is a good proxy for this
            # ServicePassword

            # this is just a temp spot to import the licence from... Should we try and get it from the api?
            # LicenceFile

            # this is just for logging for the DSC Resource
            # LogDir = "c:\temp"

            # cant check this easily... Should we try and get it from the api?
            # HighAvailabilityMode = "Leader"

            # cant check this easily... Dont even think its possible to get from the api
            # MasterKey = "StubMasterKey"
            return $true
        }

        'Absent'
        {
            return -not $fileExists
        }
    }

}

function Invoke-AndAssert {
    param (
            $cmd,
            $LogFile
    )

    # Append the command to be run to the cmdlog
    Add-Content -Path $LogFile -Value $cmd
    Write-Verbose $cmd

    $output = Invoke-Expression $cmd

    Write-Verbose ($output -join "`n")

    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null)
    {
        throw "Command returned exit code $LASTEXITCODE"
    }
}

function Import-ServerConfigFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    Write-Verbose "Importing server configuration file from '$Path'"

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

    $result = [pscustomobject] @{
        OctopusCommunicationsServicesPort                      = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Communications.ServicesPort"]/text()').Value
        OctopusHome                                            = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Home"]/text()').Value
        OctopusServerNodeName                                  = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Server.NodeName"]/text()').Value
        OctopusStorageExternalDatabaseConnectionString         = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Storage.ExternalDatabaseConnectionString"]/text()').Value
        OctopusStorageMasterKey                                = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Storage.MasterKey"]/text()').Value
        OctopusUpgradesAllowChecking                           = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Upgrades.AllowChecking"]/text()').Value -eq "true"
        OctopusUpgradesIncludeStatistics                       = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Upgrades.IncludeStatistics"]/text()').Value -eq "true"
        OctopusWebPortalAuthenticationMode                     = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.WebPortal.AuthenticationMode"]/text()').Value
        OctopusWebPortalForceSsl                               = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.WebPortal.ForceSsl"]/text()').Value -eq "true"
        OctopusWebPortalListenPrefixes                         = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.WebPortal.ListenPrefixes"]/text()').Value
        OctopusWebPortalAllowFormsAuthenticationForDomainUsers = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.WebPortal.AllowFormsAuthenticationForDomainUsers"]/text()').Value -ne "false"
    }

    if ($result.OctopusWebPortalAuthenticationMode -eq '0')
    {
        $result.OctopusWebPortalAuthenticationMode = 'UsernamePassword'
    }
    elseif ($result.OctopusWebPortalAuthenticationMode -eq '1')
    {
        $result.OctopusWebPortalAuthenticationMode = 'Domain'
    }

    return $result
}

function Get-OctopusDeployService {
    
    $service = (Get-WmiObject win32_service | ?{$_.PathName -like '*Octopus\Octopus.Server.exe*'} | select State, PathName, StartName)
    if ($null -eq $service) {
        return $null
    }

    $service.PathName -match ".* --instance=`"(.*)`"" | out-null

    return [pscustomobject] @{
        InstanceName = $matches[1]
        UserName = $service.StartName
        ServiceStatus = $service.State
    }
}

