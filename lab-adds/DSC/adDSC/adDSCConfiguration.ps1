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

        [Parameter(Mandatory)]
        [string]$domain,

        [Parameter(Mandatory)]
        [string]$childDomain,
        
    
        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    )

    $wmiDomain      = Get-WmiObject Win32_NTDomain
    $shortDomain    = $childDomain
    $DomainName     = $domain
    $ComputerName   = $wmiDomain[0].PSComputerName
    $server="$ComputerName.$shortdomain.$DomainName"

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
                $shortDomain    = $using:shortDomain
                $DomainName     = $using:DomainName
                $ComputerName   = $wmiDomain[0].PSComputerName
                $segments = @()
                $segments += $shortDomain
                $segments += ($DomainName).Split('.')
                $path = [string]::Join(", ", ($segments | % { "DC={0}" -f $_ }))
                New-ADOrganizationalUnit -Name "OrgUsers" -Path $path -Server $using:Server
            }
            GetScript =  { @{} }
            TestScript = {                 
                $test=Get-ADOrganizationalUnit -Server $using:Server -Filter 'Name -like "OrgUsers"'
                return ($test -ine $null)
            }
        }

        Script AddTestUsers
        {
            SetScript = {
                $wmiDomain = $using:wmiDomain
                $shortDomain    = $using:shortDomain
                $DomainName     = $using:DomainName
                $ComputerName   = $wmiDomain[0].PSComputerName
                $mailDomain=$shortdomain.$DomainName
                $server="$ComputerName.$shortdomain.$DomainName"
                $segments = @()
                $segments += $using:shortDomain 
                $segments += ($using:DomainName).Split('.')
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
                $user = get-aduser -filter {SamAccountName -eq $samname} -server $using:Server -ErrorAction SilentlyContinue
                return ($user -ine $null)
            }
            DependsOn  = '[Script]CreateOU'
        }
        Script AddGroups
        {
            SetScript = {
                $segments = @()
                $segments += $using:shortDomain 
                $segments += ($using:DomainName).Split('.')
                
                $OU = "OU=OrgUsers, {0}" -f [string]::Join(", ", ($segments | % { "DC={0}" -f $_ }))
                $Users = $using:usersArray

                New-ADGroup -Name "Finance" -SamAccountName Finance -GroupCategory Security -GroupScope Global -DisplayName "Finance" -Path $ou -Description "Members of this group are Finance staff" -Server $using:Server

                New-ADGroup -Name "HR" -SamAccountName HR -GroupCategory Security -GroupScope Global -DisplayName "HR" -Path $ou -Description "Members of this group are HR staff" -server $using:Server

                Add-ADgroupMember -Identity Finance -Members $users[0].'SAM',$users[1].'SAM' -server $using:Server
                Add-ADgroupMember -Identity HR -Members $users[2].'SAM' -server $using:Server


            }
            GetScript =  { @{} }
            TestScript = { 
				$group = get-adgroup -filter {samaccountname -eq "finance"} -server $using:Server
                return ($group -ine $null)
            }
            DependsOn  = '[Script]AddTestUsers'
        }
    }
}