[CmdletBinding()]
param()
Import-Module .\ps_modules\VstsTaskSdk

# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation
try {
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

    $authScheme = ''

    $serviceNameInput = Get-VstsInput -Name ConnectedServiceNameSelector -Default 'ConnectedServiceName'
    $serviceName = Get-VstsInput -Name $serviceNameInput -Default (Get-VstsInput -Name DeploymentEnvironmentName)
    if (!$serviceName)
    {
            Get-VstsInput -Name $serviceNameInput -Require
    }

    $endpoint = Get-VstsEndpoint -Name $serviceName -Require

    Write-Host "TenantID: "$endpoint.Auth.Parameters.TenantId
    Write-Host "spnKey: "$endpoint.Auth.Parameters.ServicePrincipalKey
    Write-Host "spnId: "$endpoint.Auth.Parameters.ServicePrincipalId



    if($endpoint)
    {
        $authScheme = $endpoint.Auth.Scheme 
    }

    Write-Verbose "AuthScheme $authScheme"
    
    

    
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


    if ($restore) {    
        Write-Output "Iniciando restore..."
        $backup = Get-AzureRmWebAppBackupList -ResourceGroupName $webAppResourceGroupName -Name $webappname `
            | where { $_.BackupName -contains $backupname } `
            | Select-Object -Last 1 | sort { $_.BackupId } -Descending
    
        Write-Output "Backup"
        Write-Output $backup

        $backup | Restore-AzureRmWebAppBackup -Overwrite

        return
    }


    Write-Output "Iniciando backup...."
    $backup = New-AzureRmWebAppBackup -ResourceGroupName $webAppResourceGroupName -Name $webappname `
        -StorageAccountUrl $sasUrl -BackupName $backupname 
    
    do {
        Write-Output "Status do backup...."
        $statusBackup = Get-AzureRmWebAppBackup -ResourceGroupName $webAppResourceGroupName -Name $webappname -BackupId $backup.BackupId

        Write-Output $statusBackup 

        Start-Sleep -s 10
    }while ($statusBackup.BackupStatus -eq "InProgress") 
        
}
catch {
    Write-Error "Ocorreu um erro ao realizar o backup:"
    Write-Error $_.Exception.Message
}

