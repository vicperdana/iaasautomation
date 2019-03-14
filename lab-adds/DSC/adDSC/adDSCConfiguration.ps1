$DscWorkingFolder = $PSScriptRoot

configuration DomainController
{
   param
   (
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds,


		[Parameter(Mandatory)]
		[Object]$usersArray,

		[Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$UserCreds,
        
    
        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    )

    $wmiDomain      = Get-WmiObject Win32_NTDomain
    $shortDomain    = $wmiDomain[0].DomainName
    $DomainName     = $wmidomain[0].DnsForestName
    $ComputerName   = $wmiDomain[0].PSComputerName

    $CertPw         = $AdminCreds.Password
    $ClearPw        = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($CertPw))
	$ClearDefUserPw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($UserCreds.Password))

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${shortDomain}\$($Admincreds.UserName)", $Admincreds.Password)
    
    Node 'localhost'
    {
        LocalConfigurationManager
        {
            DebugMode = 'All'
            RebootNodeIfNeeded = $true
        }

        Script CreateOU
        {
            SetScript = {
                $wmiDomain = $using:wmiDomain
                $segments = @()
                $segments += $wmiDomain[0].DomainName
                $segments += $wmiDomain[0].DnsForestName.Split('.')
                $path = [string]::Join(", ", ($segments | % { "DC={0}" -f $_ }))
                New-ADOrganizationalUnit -Name "OrgUsers" -Path $path
            }
            GetScript =  { @{} }
            TestScript = { 
                $test=Get-ADOrganizationalUnit -Filter 'Name -like "OrgUsers"' -ErrorAction SilentlyContinue
                return ($test -ine $null)
            }
        }

        Script AddTestUsers
        {
            SetScript = {
                $wmiDomain = Get-WmiObject Win32_NTDomain
                $mailDomain=(Get-WmiObject Win32_ComputerSystem).Domain
                $server="$($wmiDomain[0].PSComputerName).$($wmiDomain[0].DomainName).$($wmiDomain[0].DnsForestName)"
                $segments = @()
                $segments += $wmiDomain[0].DomainName
                $segments += $wmiDomain[0].DnsForestName.Split('.')
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
        Script AddGroups
        {
            SetScript = {
                $wmiDomain = Get-WmiObject Win32_NTDomain
                $segments = @()
                $segments += $wmiDomain[0].DomainName
                $segments += $wmiDomain[0].DnsForestName.Split('.')
                
                $OU = "OU=OrgUsers, {0}" -f [string]::Join(", ", ($segments | % { "DC={0}" -f $_ }))
                $Users = $using:usersArray

                New-ADGroup -Name "Finance" -SamAccountName Finance -GroupCategory Security -GroupScope Global -DisplayName "Finance" -Path $ou -Description "Members of this group are Finance staff"

                New-ADGroup -Name "HR" -SamAccountName HR -GroupCategory Security -GroupScope Global -DisplayName "HR" -Path $ou -Description "Members of this group are HR staff"

                Add-ADgroupMember -Identity Finance -Members $users[0].'SAM',$users[1].'SAM'
                Add-ADgroupMember -Identity HR -Members $users[2].'SAM'


            }
            GetScript =  { @{} }
            TestScript = { 
				$group = get-adgroup -filter {samaccountname -eq "finance"}
                return ($group -ine $null)
            }
            DependsOn  = '[Script]AddTestUsers'
        }
    }
}