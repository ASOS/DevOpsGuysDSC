
<#

  .SYNOPSIS
    Checks the Octopus server to ensure that the named environment exists

  .DESCRIPTION
    It is not pssible to create environments from the command line tool so this resource
    uses the Octopus Client to programtically see if it exists on the server and if it
    does not it will create it.

#>

. "$PSScriptRoot\..\..\OctopusCommon.ps1"

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Environment
	)

	importOctopusLibs

	# Determine if the environment already exists
	# Create the endpoint and the repository
	$endpoint = new-object Octopus.Client.OctopusServerEndpoint $url, $apikey
	$repository = new-object octopus.client.octopusrepository $endpoint

	$environment_exists = $repository.environments.FindByName($environment)

	return @{
		environment = $environment_exists
	}
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Environment,

		[ValidateSet("Ensure","Present")]
		[System.String]
		$Ensure,

		[System.String]
		$ApiKey,

		[System.String]
		$Url,

		[System.String]
		$Description
	)

	importOctopusLibs

	# Create the endpoint and the repository
	$endpoint = new-object Octopus.Client.OctopusServerEndpoint $url, $apikey
	$repository = new-object octopus.client.octopusrepository $endpoint

	# Craete the environment object hashtable to create the environment within
	$env_properties = @{
		name = $environment
	}

	switch ($Ensure) {
		"Present" {

			Write-Verbose ("Creating new Octopus Environment: {0}" -f $environment)

			# If an environment description has been specified add it here
			if (![String]::IsNullOrEmpty($description)) {
				$env_properties.description = $description
			}

			# Call the method to add the new environment
			$env_object = New-Object Octopus.Client.Model.EnvironmentResource -Property $env_properties
			$repository.Environments.Create($env_object) | Out-Null
		}

		"Absent" {

			Write-Verbose ("Removing Octopus environment: {0}" -f $environment)

			# Call the method to add the new environment
			$env_object = New-Object Octopus.Client.Model.EnvironmentResource -Property $env_properties
			$repository.Environments.Delete($env_object) | Out-Null
		}
	}
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Environment,

		[ValidateSet("Ensure","Present")]
		[System.String]
		$Ensure,

		[System.String]
		$ApiKey,

		[System.String]
		$Url,

		[System.String]
		$Description
	)

	importOctopusLibs

	# Set the value of the test to return
	$test = $true

	$status = Get-TargetResource -environment $environment

	# if the environment exists is null set the test to false
	if ([String]::IsNullOrEmpty($status.environment)) {
		$test = $false
	} else {
		Write-Verbose ("Octopus environment exists: {0}" -f $environment)
	}

	# if the Ensure is absent then reverse the test
	if ($Ensure -eq "Absent") {
		$test = -Not $test
	}

	return $test

}

function importOctopusLibs {

	# Find the path to the executable for the tentacle so that the required libraries can be Added
	$tentacle_exe = Get-TentacleExecutablePath
	write-verbose ("Tentacle Path: {0}" -f $tentacle_exe)
	$tentacle_home = Split-Path -Parent -Path $tentacle_exe

	# import the two libs that are required
	foreach ($type in @("Newtonsoft.json.dll", "Octopus.Client.dll")) {

		# build up the full path to the libs
		$path = "{0}\{1}" -f $tentacle_home, $type

		$assemblyBytes = [System.IO.File]::ReadAllBytes($path);
		$assemblyLoaded = [System.Reflection.Assembly]::Load($assemblyBytes);
	}
}

Export-ModuleMember -Function *-TargetResource

