[CmdletBinding()]
param()

Import-Module .\ps_modules\VstsTaskSdk

# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation

Import-VstsLocStrings "$PSScriptRoot\Task.json"
    
$targetBranch = Get-VstsInput -Name TargetBranch
$autoComplete = Get-VstsInput -Name AutoComplete

$sourceBranch = ($env:RELEASE_ARTIFACTS_APP_SOURCEBRANCH).Replace("refs/heads/", "")
$headers = @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"}
$url = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_apis/git/repositories/$($env:RELEASE_ARTIFACTS_APP_REPOSITORY_NAME)/pullRequests?api-version=4.1"
$body = ConvertTo-Json @{sourceRefName="$env:RELEASE_ARTIFACTS_APP_SOURCEBRANCH";targetRefName="refs/heads/$targetBranch";title="[$env:RELEASE_ARTIFACTS_INFRASTRUCTUREASCODE_BUILDNUMBER] $env:RELEASE_ARTIFACTS_INFRASTRUCTUREASCODE_DEFINITIONNAME solicitou um merge da '$sourceBranch' para a '$targetBranch'";description="$env:RELEASE_ARTIFACTS_INFRASTRUCTUREASCODE_BUILDNUMBER"}
$ctype = "application/json"

Write-Host "URL: "$url
Write-Host "Body: $body"
Write-Host "Repo: $env:RELEASE_ARTIFACTS_APP_REPOSITORY_NAME"
Write-Host "Source Branch: $env:RELEASE_ARTIFACTS_APP_SOURCEBRANCH"

$response = Invoke-WebRequest -Uri $url -Method POST -UseBasicParsing -Headers $headers -Body $body -ContentType $ctype  
if ( $response.StatusCode -ne 201 ) {
	Write-Host "##vso[task.logissue type=error]Falha ao criar Pull Request - $response.StatusCode $response.StatusDescription"
	Write-Host "##vso[task.complete result=Failed]"
	return 1
}

Write-Host "Pull Request criado para a branch $targetBranch"

if($autoComplete -eq "true")
{
	Write-Host "Completando Pull Request para a branch $targetBranch"

	$autoCompleteId = @{id=$env:RELEASE_REQUESTEDFOREMAIL}
	$completionOptions = @{squashMerge="false";mergeCommitMessage="Merge - $sourceBranch -> $targetBranch"}

	$body = @{autoCompleteSetBy=$autoCompleteId;completionOptions=$completionOptions} | ConvertTo-Json -Compress
	
	$resp = ($response | ConvertFrom-Json)

	Write-Host "resp: "$resp

	$url = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_apis/git/repositories/$($env:RELEASE_ARTIFACTS_APP_REPOSITORY_NAME)/pullRequests/$($resp.pullRequestId)?api-version=4.1"	
	$ctype = "application/json"

	Write-Host "Body: $body"
	Write-Host "URL: $url"
	Write-Host "Response: $response"

	$response = Invoke-WebRequest -Uri $url -Method PATCH -UseBasicParsing -Headers $headers -Body $body -ContentType $ctype  
	if ( $response.StatusCode -ne 201 ) {
		Write-Host "##vso[task.logissue type=error]Falha ao criar Pull Request - $response.StatusCode $response.StatusDescription"
		Write-Host "##vso[task.complete result=Failed]"
		return 1
	}

}

return 0