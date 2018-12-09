[CmdletBinding()]
param()

Import-Module .\ps_modules\VstsTaskSdk

# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation
# try {
Import-VstsLocStrings "$PSScriptRoot\Task.json"

    
$storageAccountResourceGroupName = Get-VstsInput -Name storageAccountResourceGroupName
$storagename = Get-VstsInput -Name storagename
$containerName = Get-VstsInput -Name containerName
$webappname = Get-VstsInput -Name webappname
$webAppResourceGroupName = Get-VstsInput -Name webAppResourceGroupName
$restore = Get-VstsInput -Name restore



#formata o nome do arquivo e diretorios
$releaseId = $env:RELEASE_RELEASENAME
$environmentName = $env:RELEASE_ENVIRONMENTNAME
$backupname = "$webappname/$releaseId/$environmentName/$releaseId"



# $serviceNameInput = Get-VstsInput -Name ConnectedServiceNameSelector -Default 'ConnectedServiceName'
# $serviceName = Get-VstsInput -Name $serviceNameInput -Default (Get-VstsInput -Name DeploymentEnvironmentName)
# if (!$serviceName) {
#     Get-VstsInput -Name $serviceNameInput -Require
# }

    

# Write-Output "service endpoint: $serviceNameInput"
# $vstsEndpoint = Get-VstsEndpoint -Name $serviceNameInput -Require
# # if ($vstsEndpoint.Auth.Scheme -ne 'ServicePrincipal') {
# #     throw "$($vstsEndpoint.Auth.Scheme) endpoint not supported"
# # }

Write-Output "Getting vsts endpoint..."
$serviceNameInput = Get-VstsInput -Name ConnectedServiceNameSelector -Default 'ConnectedServiceName'
 Write-Host $serviceNameInput
 $serviceName = Get-VstsInput -Name $serviceNameInput -Default (Get-VstsInput -Name DeploymentEnvironmentName)

 Write-Host $serviceName
        if (!$serviceName) {
            # Let the task SDK throw an error message if the input isn't defined.
            Get-VstsInput -Name $serviceNameInput -Require
        }

        $vstsEndpoint = Get-VstsEndpoint -Name $serviceName -Require

        Write-Host "TenantId: $($vstsEndpoint.Auth.Parameters.TenantId)"

$cred = New-Object System.Management.Automation.PSCredential(
    $vstsEndpoint.Auth.Parameters.ServicePrincipalId,
    (ConvertTo-SecureString $vstsEndpoint.Auth.Parameters.ServicePrincipalKey -AsPlainText -Force))
Login-AzureRmAccount -Credential $cred -ServicePrincipal -TenantId $vstsEndpoint.Auth.Parameters.TenantId -SubscriptionId $vstsEndpoint.Data.SubscriptionId

Write-Output Get-AzureRmResourceGroup

    
Write-Output "Obtendo Storage Account..."
$storage = Get-AzureRmStorageAccount -ResourceGroupName $storageAccountResourceGroupName -Name $storagename
       
if (-Not ((Get-AzureStorageContainer -Context $storage.Context).Name -contains $containerName)) {
    Write-Output "Criando o storage container"
    New-AzureStorageContainer -Name $containerName -Context $storage.Context
    # $container = Get-AzureRmStorageContainer -ResourceGroupName $storageAccountResourceGroupName -Name $containerName -StorageAccountName $storagename
}

Write-Output "Criando SAS para o container"
$sasUrl = New-AzureStorageContainerSASToken -Name $containerName -Permission rwdl `
    -Context $storage.Context -ExpiryTime (Get-Date).AddMonths(1) -FullUri

Write-Output "Restore: $restore"



# if ($restore) {    
#     Write-Output "Iniciando restore..."
#     $backup = Get-AzureRmWebAppBackupList -ResourceGroupName $webAppResourceGroupName -Name $webappname `
#         | where { $_.BackupName -contains $backupname } `
#         | Select-Object -Last 1 | sort { $_.BackupId } -Descending
    
#     Write-Output "Backup"
#     Write-Output $backup

#     $backup | Restore-AzureRmWebAppBackup -Overwrite

#     return
# }


Write-Output "Iniciando backup...."
$backup = New-AzureRmWebAppBackup -ResourceGroupName $webAppResourceGroupName -Name $webappname `
    -StorageAccountUrl $sasUrl -BackupName $backupname 
    
do {
    Write-Output "Status do backup...."
    $statusBackup = Get-AzureRmWebAppBackup -ResourceGroupName $webAppResourceGroupName -Name $webappname -BackupId $backup.BackupId

    Write-Output $statusBackup 

    Start-Sleep -s 10
}while ($statusBackup.BackupStatus -eq "InProgress") 
        
# }
# catch {
#     Write-Error "Ocorreu um erro ao realizar o backup:"
#     Write-Error $_.Exception.Message
# }

