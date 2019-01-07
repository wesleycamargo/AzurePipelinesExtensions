[CmdletBinding()]
param()

Import-Module .\ps_modules\VstsTaskSdk

# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation

Import-VstsLocStrings "$PSScriptRoot\Task.json"
    
$email = Get-VstsInput -Name EmailCredential
$pass = Get-VstsInput -Name PassCredential

$smtpServer = Get-VstsInput -Name SMTPServer
$to = Get-VstsInput -Name emailTo
$from = Get-VstsInput -Name emailFrom
$template = Get-VstsInput -Name subject
$subject = Get-VstsInput -Name templateDirectory

$body = Get-Content $template
Write-Host $body
$msg = new-object Net.Mail.MailMessage
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$smtp.EnableSsl = $true
$msg.From = $from
$msg.To.Add("$to")
$msg.BodyEncoding = [system.Text.Encoding]::Unicode
$msg.SubjectEncoding = [system.Text.Encoding]::Unicode
$msg.IsBodyHTML = $true 
$msg.Subject = $subject
$msg.Body = $body 
$SMTP.Credentials = New-Object System.Net.NetworkCredential("$email", "$pass");
$smtp.Send($msg)