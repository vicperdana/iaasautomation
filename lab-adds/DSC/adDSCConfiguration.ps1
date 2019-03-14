$DscWorkingFolder = $PSScriptRoot

configuration DomainController
{
   param
   (
        [Parameter(Mandatory)]
        [String]$Subject,


        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds,


		[Parameter(Mandatory)]
		[Object]$usersArray,

		[Parameter(Mandatory)]
		[System.Management.Automation.PSCredential]$UserCreds,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    )
    
    $wmiDomain      = Get-WmiObject Win32_NTDomain -Filter "DnsForestName = '$( (Get-WmiObject Win32_ComputerSystem).Domain)'"
    $shortDomain    = $wmiDomain.DomainName
    $DomainName     = $wmidomain.DnsForestName
    $ComputerName   = $wmiDomain.PSComputerName
    $CARootName     = "$($shortDomain.ToLower())-$($ComputerName.ToUpper())-CA"
    $CAServerFQDN   = "$ComputerName.$DomainName"

	

    $CertPw         = $AdminCreds.Password
    $ClearPw        = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($CertPw))
	$ClearDefUserPw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($UserCreds.Password))

    Import-DscResource -ModuleName xComputerManagement,xNetworking,xSmbShare,xAdcsDeployment,xCertificate,PSDesiredStateConfiguration

    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${shortDomain}\$($Admincreds.UserName)", $Admincreds.Password)
    
    Node 'localhost'
    {
        LocalConfigurationManager
        {
            DebugMode = 'All'
            RebootNodeIfNeeded = $true
        }

        WindowsFeature ADCS-Cert-Authority
        {
            Ensure = 'Present'
            Name = 'ADCS-Cert-Authority'
        }

        WindowsFeature RSAT-ADCS-Mgmt
        {
            Ensure = 'Present'
            Name = 'RSAT-ADCS-Mgmt'
        }

        File SrcFolder
        {
            DestinationPath = "C:\src"
            Type = "Directory"
            Ensure = "Present"
        }

        xSmbShare SrcShare
        {
            Ensure = "Present"
            Name = "src"
            Path = "C:\src"
            FullAccess = @("Domain Admins","Domain Computers")
            ReadAccess = "Authenticated Users"
            DependsOn = "[File]SrcFolder"
        }

        xADCSCertificationAuthority ADCS
        {
            Ensure = 'Present'
            Credential = $DomainCreds
            CAType = 'EnterpriseRootCA'
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority'             
        }

        WindowsFeature ADCS-Web-Enrollment
        {
            Ensure = 'Present'
            Name = 'ADCS-Web-Enrollment'
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority','[WindowsFeature]ADCS-Cert-Authority'
        }

        xADCSWebEnrollment CertSrv
        {
            Ensure = 'Present'
            IsSingleInstance = 'Yes'
            Credential = $DomainCreds
            DependsOn = '[WindowsFeature]ADCS-Web-Enrollment','[xADCSCertificationAuthority]ADCS'
        }

		Script ExportRoot
		{
			SetScript = {
							$arr       = $($using:DomainName).split('.')
							$d         = $($using:shortDomain).ToLower()
							$c         = $($using:ComputerName).ToUpper()
							$shortname = "$d-$c-CA"
                            $rootName  = "CN={0}, {1}" -f $shortname, [string]::Join(", ", ($arr | % { "DC={0}" -f $_ }))

							$rootcert  = Get-ChildItem Cert:\LocalMachine\CA | where {$_.Subject -eq "$rootName"}
							if ($rootcert -eq $null) {
							    Write-Verbose "ERROR: ROOT CERT `"$rootName`" NOT FOUND, cancelling cert export"
							} else {
								$root      = if ($rootcert.GetType().BaseType.Name -eq "Array") {$rootCert[0]} else {$rootCert}
								Export-Certificate -FilePath "c:\src\$shortname.cer" -Cert $root
							}

						}
			TestScript = {
					$arr       = $($using:DomainName).split('.')
					$d         = $($using:shortDomain).ToLower()
					$c         = $($using:ComputerName).ToUpper()
					$shortname = "$d-$c-CA"
					return Test-Path "C:\src\$shortname.cer"
			}
			GetScript = { @{} }
			DependsOn = '[xADCSWebEnrollment]CertSrv'
		}

        Script InstallAADConnect
        {
            SetScript = {
                $AADConnectDLUrl="https://download.microsoft.com/download/B/0/0/B00291D0-5A83-4DE7-86F5-980BC00DE05A/AzureADConnect.msi"
                $exe="$env:SystemRoot\system32\msiexec.exe"

                $tempfile = [System.IO.Path]::GetTempFileName()
                $folder = [System.IO.Path]::GetDirectoryName($tempfile)

                $webclient = New-Object System.Net.WebClient
                $webclient.DownloadFile($AADConnectDLUrl, $tempfile)

                Rename-Item -Path $tempfile -NewName "AzureADConnect.msi"
                $MSIPath = $folder + "\AzureADConnect.msi"

                Invoke-Expression "& `"$exe`" /i $MSIPath /qn /passive /forcerestart"
            }

            GetScript =  { @{} }
            TestScript = { 
                return Test-Path "$env:TEMP\AzureADConnect.msi" 
            }
        }

        Script CreateOU
        {
            SetScript = {
                $wmiDomain = Get-WmiObject Win32_NTDomain -Filter "DnsForestName = '$( (Get-WmiObject Win32_ComputerSystem).Domain)'"
                $segments = $wmiDomain.DnsForestName.Split('.')
                $path = [string]::Join(", ", ($segments | % { "DC={0}" -f $_ }))
                New-ADOrganizationalUnit -Name "OrgUsers" -Path $path
            }
            GetScript =  { @{} }
            TestScript = { 
                $test=Get-ADOrganizationalUnit -Server "$using:ComputerName.$using:DomainName" -Filter 'Name -like "OrgUsers"' -ErrorAction SilentlyContinue
                return ($test -ine $null)
            }
        }

        Script AddTestUsers
        {
            SetScript = {
                $wmiDomain = Get-WmiObject Win32_NTDomain -Filter "DnsForestName = '$( (Get-WmiObject Win32_ComputerSystem).Domain)'"
                $mailDomain=$wmiDomain.DnsForestName
                $server="$($wmiDomain.PSComputerName).$($wmiDomain.DnsForestName)"
                $segments = $wmiDomain.DnsForestName.Split('.')
                $OU = "OU=OrgUsers, {0}" -f [string]::Join(", ", ($segments | % { "DC={0}" -f $_ }))
                
                $folder=$using:DscWorkingFolder

				$clearPw = $using:ClearDefUserPw
				$Users = $using:usersArray

                foreach ($User in $Users)
                {
                    $Displayname = $User.'FName' + " " + $User.'LName'
                    $UserFirstname = $User.'FName'
                    $UserLastname = $User.'LName'
                    $SAM = $User.'SAM'
                    $UPN = $User.'FName' + "." + $User.'LName' + "@" + $Maildomain
                    #$Password = $User.'Password'
                    $Password = $clearPw
                    "$DisplayName, $Password, $SAM"
                    New-ADUser `
                        -Name "$Displayname" `
                        -DisplayName "$Displayname" `
                        -SamAccountName $SAM `
                        -UserPrincipalName $UPN `
                        -GivenName "$UserFirstname" `
                        -Surname "$UserLastname" `
                        -Description "$Description" `
                        -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
                        -Enabled $true `
                        -Path "$OU" `
                        -ChangePasswordAtLogon $false `
                        -PasswordNeverExpires $true `
                        -server $server `
                        -EmailAddress $UPN
                }
            }
            GetScript =  { @{} }
            TestScript = { 
				$Users = $using:usersArray
                $samname=$Users[0].'SAM'
                $user = get-aduser -filter {SamAccountName -eq $samname} -ErrorAction SilentlyContinue
                return ($user -ine $null)
            }
            DependsOn  = '[Script]CreateOU'
        }
		
        #using service credentials for ADFS for now
		Script AddTools
        {
            SetScript  = {
				# Install AAD Tools
					md c:\temp -ErrorAction Ignore
					Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

					#Install-Module -Name Azure -AllowClobber -Force
					#Install-Module -Name AzureRM -AllowClobber -Force

					Install-Module -Name MSOnline -Force

					Install-Module -Name AzureAD -Force

					Install-Module -Name AzureADPreview -AllowClobber -Force
                }

            GetScript =  { @{} }
            TestScript = { 
                $key=Get-Module -Name MSOnline -ListAvailable
                return ($key -ine $null)
            }
            #Credential = $DomainCreds
            #PsDscRunAsCredential = $DomainCreds

            DependsOn = '[xADCSWebEnrollment]CertSrv'
        }
		

        <#
        Script UpdateAdfsSiteGPO
        {
            SetScript = {
                $SiteName = $using:Subject
                $TargetGPO = Get-GPO -Name "Default Domain Policy"
                $ZoneName = '1'
                $TargetHive = 'HKEY_LOCAL_MACHINE'
                $BaseKey = 'Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings'
                $Key = "$($TargetHive)\$($BaseKey)\ZoneMapKey"

                Set-GPRegistryValue -Guid $TargetGPO.Id -Additive -Key $Key -ValueName $SiteName -Type "String" -Value "1" | Out-Null
            }
            GetScript =  { @{} }
            TestScript = { 
                $CurrKey = Get-GPRegistryValue -Guid $TargetGPO.Id -Key $Key -ValueName $SiteName -ErrorAction SilentlyContinue
                return ($CurrKey -ine $null)
            }
        }
        #>
    }
}