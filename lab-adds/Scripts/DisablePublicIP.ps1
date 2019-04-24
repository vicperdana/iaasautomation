param (
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName

)

$ErrorActionPreference = "Stop"
$azurevm = Get-AzureRMVM -ResourceGroupName $resGroupName -Name $vmName
#Write-output "AzureVM variable :" $azurevm
$NicId = $azurevm | foreach {$_.NetworkProfile.NetworkInterfaces.Id}
#Write-output "NicId variable $NicId"
$NicArmObject = Get-AzureRmResource -ResourceId $NicId
$nic = Get-AzureRmNetworkInterface -Name $NicArmObject.Name -ResourceGroupName $NicArmObject.ResourceGroupName
$nic.IpConfigurations.publicipaddress.id = $null
Set-AzureRmNetworkInterface -NetworkInterface $nic
