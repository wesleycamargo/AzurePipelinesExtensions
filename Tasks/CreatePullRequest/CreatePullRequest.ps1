[CmdletBinding()]
param()

###################################################
# Init Script
###################################################

Import-Module .\ps_modules\VstsTaskSdk
Trace-VstsEnteringInvocation $MyInvocation
Import-VstsLocStrings "$PSScriptRoot\Task.json"

###################################################

###################################################
# Global variables
###################################################

$targetBranch = Get-VstsInput -Name TargetBranch
$PATuser = Get-VstsInput -Name PATuser
$PATtoken = Get-VstsInput -Name PATtoken
$autoComplete = Get-VstsInput -Name AutoComplete

$sourceBranch = ($env:RELEASE_ARTIFACTS_APP_SOURCEBRANCH).Replace("refs/heads/", "")
$headers = @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"}
$ctype = "application/json"

###################################################

<#
.SYNOPSIS
Check if exists pull request

.DESCRIPTION
Check if exists any active pull request from source branch to target branch

#>
function PullRequestExists {
     $url = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_apis/git/pullrequests?searchCriteria.sourceRefName=$env:RELEASE_ARTIFACTS_APP_SOURCEBRANCH&searchCriteria.targetRefName=refs/heads/$targetBranch&searchCriteria.repositoryId=$env:RELEASE_ARTIFACTS_APP_REPOSITORY_ID"
    #verifica se ja existe PR
    Write-Host "Uri: $url"
    $response = (Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing -Headers $headers -Body $body -ContentType $ctype) | ConvertFrom-Json
    
    Write-Host "Response: $response"
    Write-Host "Count: $($response.count)"
    Write-Host "Value: $($response.value)"

    if($response.count -ne 0)
    {
        Write-Host "Have already an existing pull request: PullRequestID: $($response.value.pullRequestId)"
        return $response.value.pullRequestId        
    }    
    Write-Host "Does not exist any active pull requests..."
    return 0
}


<#
.SYNOPSIS
Create new pull request

.DESCRIPTION
Create a new pull request from source branch to target branch

#>
function CreatePullRequest {    
    $pullRequestId = PullRequestExists

    if ($pullRequestId -eq 0) {	      
        Write-Host "Does not exist any active pull request, creating new... "
        $url = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_apis/git/repositories/$($env:RELEASE_ARTIFACTS_APP_REPOSITORY_NAME)/pullRequests?api-version=4.1"
        $body = ConvertTo-Json @{sourceRefName = "$env:RELEASE_ARTIFACTS_APP_SOURCEBRANCH"; targetRefName = "refs/heads/$targetBranch"; title = "[$env:RELEASE_DEFINITIONNAME] $env:RELEASE_REQUESTEDFOREMAIL solicitou um merge da '$sourceBranch' para a '$targetBranch'"; description = "Build Number: $env:BUILD_BUILDNUMBER"}
	
        $response = Invoke-WebRequest -Uri $url -Method POST -UseBasicParsing -Headers $headers -Body $body -ContentType $ctype  
    
        Write-Host "Status code: $($response.StatusCode)"

        $resp = $response | ConvertFrom-Json

        Write-Host "Status code json convert: $($resp.StatusCode)"
    
        if ( $response.StatusCode -ne 201 ) {
            Write-Host "##vso[task.logissue type=error]Falha ao criar Pull Request - $response.StatusCode $response.StatusDescription"
            Write-Host "##vso[task.complete result=Failed]"
            return 1
        }  
	
        Write-Host "Created pull request to branch '$targetBranch'"    

        $r = $response | ConvertFrom-Json

        Write-Host "Response: $r"
        Write-Host "PRID: $($r.pullRequestId)"
        return $r.pullRequestId
    }
    else {
        Write-Host "Have already a pull request from branch $sourceBranch to $targetBranch..."
        Write-Host "Pull request ID: $($response.value.pullrequestid)"
        return $pullRequestId
    }
}

function ApprovePullRequest {
    param (        
        $pullRequestId
    )
    
    Write-Host "Completing pull request to branch '$targetBranch'"

    #set auth
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $PATuser, $PATtoken)))

    $autoCompleteId = @{id="$($env:RELEASE_DEPLOYMENT_REQUESTEDFORID)"}
    $completionOptions = @{squashMerge="false";mergeCommitMessage="Merge - $sourceBranch -> $targetBranch"}    
    $setAutoCompleteJson = @{autoCompleteSetBy=$autoCompleteId;completionOptions=$completionOptions} | ConvertTo-Json -Compress

    # Construct the REST URL to obtain Build ID    
    $uri = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_apis/git/repositories/$($env:RELEASE_ARTIFACTS_APP_REPOSITORY_NAME)/pullRequests/$($pullRequestId)?api-version=4.1"	
    Write-Host "Uri: $uri" 

    $response = Invoke-RestMethod -Method PATCH -ContentType "application/json" -Headers  @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Body $setAutoCompleteJson -Uri $uri
    # $response = Invoke-RestMethod -Method PATCH -ContentType "application/json" -Headers $headers -Body $setAutoCompleteJson -Uri $uri | ConvertFrom-Json

    Write-Host "Pull request status: $($response.status)"

    return 0
}

$pullRequestId = CreatePullRequest 

Write-Host "PullRequestID: $pullRequestId" | Out-File log.txt

if ($autoComplete -eq "true") {
    Write-Host "Aproving"
    ApprovePullRequest -pullRequestId $pullRequestId
}
return 0