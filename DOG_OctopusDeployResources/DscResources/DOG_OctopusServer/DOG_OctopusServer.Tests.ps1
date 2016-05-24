#requires -Version 4.0

$modulePath = $PSCommandPath -replace '\.Tests\.ps1$', '.psm1'
$module = $null

try
{
    $prefix = [guid]::NewGuid().Guid -replace '-'
    $module = Import-Module $modulePath -Prefix $prefix -PassThru -ErrorAction Stop

    InModuleScope $module.Name {
        Describe 'Import-ServerConfigFile' {
            Context 'Fully populated file' {
                $content = @'
<?xml version="1.0" encoding="utf-8"?>
<octopus-settings xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <set key="Octopus.Communications.ServicesPort">10943</set>
  <set key="Octopus.Home">C:\Octopus</set>
  <set key="Octopus.Server.NodeName">TestVM-01</set>
  <set key="Octopus.Storage.ExternalDatabaseConnectionString">Server=tcp:octopus.database.windows.net,1433;Data Source=octopus.database.windows.net;Initial Catalog=OctopusDeploy;Persist Security Info=False;User ID=octopus;Password=Secr3t;Pooling=False;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;</set>
  <set key="Octopus.Storage.MasterKey">Fake-encrypted-master-key</set>
  <set key="Octopus.Upgrades.AllowChecking">true</set>
  <set key="Octopus.Upgrades.IncludeStatistics">true</set>
  <set key="Octopus.WebPortal.AuthenticationMode">0</set>
  <set key="Octopus.WebPortal.ForceSsl">false</set>
  <set key="Octopus.WebPortal.ListenPrefixes">https://test-octopus.example.com,http://localhost</set>
  <set key="Octopus.WebPortal.AllowFormsAuthenticationForDomainUsers">false</set>
</octopus-settings>
'@

                $content | Out-File -Encoding ascii -FilePath TestDrive:\test.xml

                It 'Imports the file properly' {
                    $imported = Import-ServerConfigFile -Path TestDrive:\test.xml

                    $imported.OctopusCommunicationsServicesPort                      | Should Be 10943
                    $imported.OctopusHome                                            | Should Be C:\Octopus
                    $imported.OctopusServerNodeName                                  | Should Be TestVM-01
                    $imported.OctopusStorageExternalDatabaseConnectionString         | Should Be "Server=tcp:octopus.database.windows.net,1433;Data Source=octopus.database.windows.net;Initial Catalog=OctopusDeploy;Persist Security Info=False;User ID=octopus;Password=Secr3t;Pooling=False;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
                    $imported.OctopusStorageMasterKey                                | Should Be "Fake-encrypted-master-key"
                    $imported.OctopusUpgradesAllowChecking                           | Should Be $true
                    $imported.OctopusUpgradesIncludeStatistics                       | Should Be $true
                    $imported.OctopusWebPortalAuthenticationMode                     | Should Be "UsernamePassword"
                    $imported.OctopusWebPortalForceSsl                               | Should Be $false
                    $imported.OctopusWebPortalListenPrefixes                         | Should Be "https://test-octopus.example.com,http://localhost"
                    $imported.OctopusWebPortalAllowFormsAuthenticationForDomainUsers | Should Be $false
                }
            }

            Context 'File with missing information' {
                $content = @'
<?xml version="1.0" encoding="utf-8"?>
<octopus-settings xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
</octopus-settings>
'@

                $content | Out-File -Encoding ascii -FilePath TestDrive:\test.xml

                It 'Imports the file without errors, assigning appropriate default values' {
                    $imported = Import-ServerConfigFile -Path TestDrive:\test.xml

                    $imported.OctopusCommunicationsServicesPort                      | Should Be $null
                    $imported.OctopusHome                                            | Should Be $null
                    $imported.OctopusServerNodeName                                  | Should Be $null
                    $imported.OctopusStorageExternalDatabaseConnectionString         | Should Be $null
                    $imported.OctopusStorageMasterKey                                | Should Be $null
                    $imported.OctopusUpgradesAllowChecking                           | Should Be $false
                    $imported.OctopusUpgradesIncludeStatistics                       | Should Be $false
                    $imported.OctopusWebPortalAuthenticationMode                     | Should Be $null
                    $imported.OctopusWebPortalForceSsl                               | Should Be $false
                    $imported.OctopusWebPortalListenPrefixes                         | Should Be $null
                    $imported.OctopusWebPortalAllowFormsAuthenticationForDomainUsers | Should Be $true
                }
             }
        }

         Describe '*-TargetResource Functions' {
             BeforeEach {
                $mockConfigFile = [pscustomobject] @{
                    OctopusCommunicationsServicesPort                      = 10943
                    OctopusHome                                            = 'StubHomeDirectory'
                    OctopusServerNodeName                                  = 'StubNodeName'
                    OctopusStorageExternalDatabaseConnectionString         = 'StubConnectionString'
                    OctopusStorageMasterKey                                = 'EncryptedMasterKey'
                    OctopusUpgradesAllowChecking                           = $true
                    OctopusUpgradesIncludeStatistics                       = $true
                    OctopusWebPortalAuthenticationMode                     = "Domain"
                    OctopusWebPortalForceSsl                               = $true
                    OctopusWebPortalListenPrefixes                         = "https://octopus.example.com,http://localhost"
                    OctopusWebPortalAllowFormsAuthenticationForDomainUsers = $false
                }
                $stubPath = 'TestDrive:\stub.xml'
                $stubLicenceFile = 'TestDrive:\licencefile.xml'

                $splat = @{
                    InstanceName = "OctopusServer"
                    Ensure = "Present"
                    ConfigFile = $stubPath
                    HomePath = "StubHomeDirectory"
                    DBConnectionString = "StubConnectionString"
                    UpgradeCheck = $true
                    UpgradeCheckStatistics = $true
                    WebAuthenticationMode = "Domain"
                    WebForceSSL = $true
                    WebListenPrefixes = "https://octopus.example.com,http://localhost"
                    CommsListenPort = 10943
                    ServerNodeName = "StubNodeName"
                    AdminUser = "Admin"
                    AdminPassword = "AdminPassword"
                    LicenceFile = $stubLicenceFile
                    ServiceAccount = "StubServiceAccount"
                    ServicePassword = "StubServicePassword"
                    LogDir = "c:\temp"
                    HighAvailabilityMode = "Leader"
                    MasterKey = "StubMasterKey"
                    AllowFormsAuthenticationForDomainUsers = $false
                }

                if (-not (Test-Path $stubPath))  {
                    New-Item -Path $stubPath -ItemType File
                }
                if (-not (Test-Path $stubLicenceFile))  {
                    Set-Content $stubLicenceFile "fake licence"
                }

                $mockServiceResult =[pscustomobject] @{
                    InstanceName = "OctopusServer"
                    UserName = "StubServiceAccount"
                    ServiceStatus = "Running"
                }
            }

             Mock Import-ServerConfigFile { return $mockConfigFile }
             Mock Get-OctopusDeployService { return $mockServiceResult }

             Context 'Get-TargetResource' {
                 It 'Returns the expected data' {
                    $config = Get-TargetResource -ConfigFile 'TestDrive:\stub.xml' -InstanceName 'Unused'

                    $config.GetType()                                 | Should Be ([hashtable])
                    $config.PSBase.Count                              | Should Be 15

                    $config['ConfigFile']                             | Should Be 'TestDrive:\stub.xml'
                    $config['InstanceName']                           | Should Be 'OctopusServer'
                    $config['Ensure']                                 | Should Be 'Present'
                    $config['HomePath']                               | Should Be 'StubHomeDirectory'
                    $config['DBConnectionString']                     | Should Be 'StubConnectionString'
                    $config['UpgradeCheck']                           | Should Be $true
                    $config['UpgradeCheckStatistics']                 | Should Be $true
                    $config['WebAuthenticationMode']                  | Should be 'Domain'
                    $config['WebForceSSL']                            | Should Be $true
                    $config['WebListenPrefixes']                      | Should Be 'https://octopus.example.com,http://localhost'
                    $config['CommsListenPort']                        | Should Be 10943
                    $config['AllowFormsAuthenticationForDomainUsers'] | Should Be $false
                    $config['ServerNodeName']                         | Should Be 'StubNodeName'
                    $config['ServiceAccount']                         | Should Be 'StubServiceAccount'
                    $config['ServiceStatus']                          | Should Be 'Running'
                 }
             }

             Context 'Test-TargetResource' {

                It 'Returns True when the file does not exist and Ensure is set to Absent' {
                    $splat['Ensure'] = 'Absent'
                    Remove-Item TestDrive:\stub.xml

                    Test-TargetResource @splat | Should Be $true
                }

                It 'Returns False when the file does not exist and Ensure is set to Present' {
                    Remove-Item TestDrive:\stub.xml

                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the file does exist and Ensure is set to Absent' {
                    $splat['Ensure'] = 'Absent'

                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns True when the configuration matches desired state' {
                    Test-TargetResource @splat | Should Be $true
                }

                It 'Returns False when the InstanceName does not match the desired state' {
                    $splat['InstanceName'] = 'Bogus'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the HomePath does not match the desired state' {
                    $splat['HomePath'] = 'Bogus'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the DBConnectionString does not match the desired state' {
                    $splat['DBConnectionString'] = 'Bogus'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the UpgradeCheck does not match the desired state' {
                    $splat['UpgradeCheck'] = $false
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the UpgradeCheckStatistics does not match the desired state' {
                    $splat['UpgradeCheckStatistics'] = $false
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the WebAuthenticationMode does not match the desired state' {
                    $splat['WebAuthenticationMode'] = 'UsernamePassword'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the WebForceSSL does not match the desired state' {
                    $splat['WebForceSSL'] = $false
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the ServerNodeName does not match the desired state' {
                    $splat['ServerNodeName'] = 'Bogus'
                    Test-TargetResource @splat | Should Be $false
                }
                
                It 'Returns False when the CommsListenPort does not match the desired state' {
                    $splat['CommsListenPort'] = 1234
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the WebListenPrefixes does not match the desired state' {
                    $splat['WebListenPrefixes'] = 'https://example.com'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the ServiceAccount does not match the desired state' {
                    $splat['ServiceAccount'] = 'Bogus'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the service is not running' {
                    $mockServiceResult.ServiceStatus = 'Stopped'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the AllowFormsAuthenticationForDomainUsers does not match the desired state' {
                    $splat['AllowFormsAuthenticationForDomainUsers'] = $true
                    Test-TargetResource @splat | Should Be $false
                }
             }

             Context 'Set-TargetResource' {
                # Mock Invoke-AndAssert 

                # It 'Creates a new instance' {
                #     throw "not implemented"

                #     Set-TargetResource @splat
                #     Assert-VerifiableMocks
                # }

                # It 'Configures the instance' {
                #     throw "not implemented"
                #     Set-TargetResource @splat
                #     Assert-MockCalled -Scope It -Times 1 Invoke-AndAssert
                # }

                # It 'Creates the database if Standalone or Leader' {
                #     throw "not implemented"
                #     Set-TargetResource @splat
                #     Assert-MockCalled -Scope It -Times 1 Invoke-AndAssert
                # }

                # It 'Creates the admin user if Standalone or Leader' {
                #     throw "not implemented"
                #     Set-TargetResource @splat
                #     Assert-MockCalled -Scope It -Times 1 Invoke-AndAssert
                # }

                # It 'Creates the admin user with password if Standalone or Leader and in UsernamePassword mode' {
                #     throw "not implemented"
                #     Set-TargetResource @splat
                #     Assert-MockCalled -Scope It -Times 1 Invoke-AndAssert
                # }

                # It 'Sets the service account' {
                #     throw "not implemented"
                #     Set-TargetResource @splat
                #     Assert-MockCalled -Scope It -Times 1 Invoke-AndAssert
                # }

                # It 'Translates the service account to replace a leading ".\" to the computer name' {
                #     throw "not implemented"
                #     Set-TargetResource @splat
                #     Assert-MockCalled -Scope It -Times 1 Invoke-AndAssert
                # }
             }
         }
    }
}
finally
{
    if ($module) { Remove-Module -ModuleInfo $module }
}
