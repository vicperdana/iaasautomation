New-AzureRmResourceGroup  -Name "rg-jenkinsBuildPoC" -Location "australiaeast" -Tag @{Environment="Dev"; Purpose="JenkinsPoC"}
New-AzureRmResourceGroupDeployment -name jenkinsTest -ResourceGroupName "rg-jenkinsBuildPoC" -TemplateFile "C:\Users\viperdan\OneDrive - Microsoft\03-CodeRepo\temp\functions\azuredeploy.json" -TemplateParameterFile "C:\Users\viperdan\OneDrive - Microsoft\03-CodeRepo\temp\functions\azuredeploy.parameters.json"
#	az ad sp create-for-rbac --name jenkins_sp --password GDJHkdjkd%^&GJJhn!
# az account list
az group deployment create --resource-group "rg-jenkinsBuildPoC" --template-file "/var/lib/jenkins/workspace/DeployLogicFunctionApp/lab-jenkins/functions/azuredeploy.json" --parameters appName=jenkinsAzureFunction
