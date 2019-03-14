$startTime=Get-Date
Write-Host "Beginning deployment at $starttime"

Import-Module Azure -ErrorAction SilentlyContinue

#DEPLOYMENT OPTIONS
    $templateToDeploy        = "azuredeploy.json"
    $templateParamToDeploy        = "azuredeploy.parameters.json"
    # MUST be unique for all your simultaneous/co-existing deployments of this ADName in the same region
    $VNetAddrSpace2ndOctet   = "1"

    # Must be unique for simultaneous/co-existing deployments
    #"master" or "dev"
    $RGName                  = "rg-addslab1"
    $DeployRegion            = "eastus"
    $Branch                  = "master"
    $AssetLocation           = "https://raw.githubusercontent.com/vicperdana/iaasautomation/master/lab-adds/"
    $userName                = "vperdana"
    $secpasswd               = 'Pass1234##!!'
    $adDomainName            = "vperdana.lab"
    $usersArray              = @(
                                @{ "FName"= "Bob";  "LName"= "Jones";    "SAM"= "bjones" },
                                @{ "FName"= "Bill"; "LName"= "Smith";    "SAM"= "bsmith" },
                                @{ "FName"= "Mary"; "LName"= "Phillips"; "SAM"= "mphillips" },
                                @{ "FName"= "Sue";  "LName"= "Jackson";  "SAM"= "sjackson" }
                               )
    $defaultUserPassword     = "P@ssw0rd"



#END DEPLOYMENT OPTIONS


#ensure we're logged in
Get-AzureRmContext -ErrorAction Stop

#deploy
$parms=@{
    "adminPassword"               = $secpasswd;
    "adminUsername"               = $userName;
    "adDomainName"                = $ADDomainName;
    "assetLocation"               = $assetLocation;
    "virtualNetworkAddressRange"  = "10.$VNetAddrSpace2ndOctet.0.0/16";
    #The first IP deployed in the AD subnet, for the DC
    #The first ADFS server deployed in the AD subnet - multiple farms will increment beyond this
    "adSubnetAddressRange"        = "10.$VNetAddrSpace2ndOctet.1.0/24";
    "dmzSubnetAddressRange"       = "10.$VNetAddrSpace2ndOctet.2.0/24";
    "cliSubnetAddressRange"       = "10.$VNetAddrSpace2ndOctet.3.0/24";
    #if multiple deployments will need to route between vNets, be sure to make this distinct between them
    "deploymentNumber"            = $VNetAddrSpace2ndOctet;
    "usersArray"                  = $usersArray;
    "defaultUserPassword"         = "P@ssw0rd";
}

$TemplateFile = "$($assetLocation)$templateToDeploy" + "?x=5"
$templateFile

$TemplateParamFile = "$($assetLocation)$templateParamToDeploy" + "?x=5"
$TemplateParamFile

try {
    Get-AzureRmResourceGroup -Name $RGName -ErrorAction Stop
    Write-Host "Resource group $RGName exists, updating deployment"
}
catch {
    $RG = New-AzureRmResourceGroup -Name $RGName -Location $DeployRegion -Tag @{ Shutdown = "true"; Startup = "false"}
    Write-Host "Created new resource group $RGName."
}
$version ++
$deployment = New-AzureRmResourceGroupDeployment -ResourceGroupName $RGName -templateUri $TemplateFile -TemplateParameterUri $TemplateParamFile -Name "addsDeploy$version"  -Force -Verbose


$endTime=Get-Date

Write-Host ""
Write-Host "Total Deployment time:"
New-TimeSpan -Start $startTime -End $endTime | Select Hours, Minutes, Seconds
