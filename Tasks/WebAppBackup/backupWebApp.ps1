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
$restoreEnvironment = Get-VstsInput -Name restoreEnvironment


#formata o nome do arquivo e diretorios
$releaseId = $env:RELEASE_RELEASENAME

Write-Output "Getting vsts endpoint..."
$serviceNameInput = Get-VstsInput -Name ConnectedServiceNameSelector -Default 'ConnectedServiceName'
$serviceName = Get-VstsInput -Name $serviceNameInput -Default (Get-VstsInput -Name DeploymentEnvironmentName)

Write-Host $serviceName
if (!$serviceName) {
    Get-VstsInput -Name $serviceNameInput -Require
}

$vstsEndpoint = Get-VstsEndpoint -Name $serviceName -Require

$cred = New-Object System.Management.Automation.PSCredential(
    $vstsEndpoint.Auth.Parameters.ServicePrincipalId,
    (ConvertTo-SecureString $vstsEndpoint.Auth.Parameters.ServicePrincipalKey -AsPlainText -Force))

Login-AzureRmAccount -Credential $cred -ServicePrincipal -TenantId $vstsEndpoint.Auth.Parameters.TenantId -SubscriptionId $vstsEndpoint.Data.SubscriptionId
    
Write-Output "Getting Storage Account..."
$storage = Get-AzureRmStorageAccount -ResourceGroupName $storageAccountResourceGroupName -Name $storagename
       
if (-Not ((Get-AzureStorageContainer -Context $storage.Context).Name -contains $containerName)) {
    Write-Output "Creating storage container"
    New-AzureStorageContainer -Name $containerName -Context $storage.Context
}

Write-Output "Creating SAS to container"
$sasUrl = New-AzureStorageContainerSASToken -Name $containerName -Permission rwdl `
    -Context $storage.Context -ExpiryTime (Get-Date).AddMonths(1) -FullUri

Write-Output "Restore: $restore"

if ($restore  -eq "true") {            
    
    $backupname = "$webappname/$releaseId/$restoreEnvironment/$releaseId"

    Write-Output "Backup Name: $backupname"
 
    Write-Output "Obtendo backups existentes"

    $backups = Get-AzureRmWebAppBackupList -ResourceGroupName $webAppResourceGroupName -Name $webappname

    Write-Output "Backups existentes:"
    Write-Output $backups

    if (($backups).BackupName -contains $backupname) {
        Write-Output "Iniciando restore..."
        $backup = Get-AzureRmWebAppBackupList -ResourceGroupName $webAppResourceGroupName -Name $webappname `
            | where { $_.BackupName -contains $backupname } `
            | Select-Object -Last 1 | sort { $_.BackupId } -Descending
    }
    else {
        Write-Host "##vso[task.logissue type=error]Nao foram encontrados backups para o environment '$restoreEnvironment'"
        Write-Host "##vso[task.complete result=Failed]"
        return 1        
    }
        
    Write-Output "Backup"
    Write-Output $backup

    $backup | Restore-AzureRmWebAppBackup -Overwrite
  
    return 0
}

$environmentName = $env:RELEASE_ENVIRONMENTNAME
$backupname = "$webappname/$releaseId/$environmentName/$releaseId"

Write-Output "Initializing backup...."
$backup = New-AzureRmWebAppBackup -ResourceGroupName $webAppResourceGroupName -Name $webappname `
    -StorageAccountUrl $sasUrl -BackupName $backupname 
    
do {
    Write-Output "Backup Status...."
    $statusBackup = Get-AzureRmWebAppBackup -ResourceGroupName $webAppResourceGroupName -Name $webappname -BackupId $backup.BackupId

    Write-Output $statusBackup 

    Start-Sleep -s 10
}while ($statusBackup.BackupStatus -eq "InProgress") 

return 0