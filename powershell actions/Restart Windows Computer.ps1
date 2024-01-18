# Note: This example is provided as an illustration only and is not supported.
# Technical support is available for the Context object, SNMP API, and scripting environment, 
# but Progress does not provide support for PowerShell or developing and debugging PowerShell active monitors or actions.
# For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
# or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration


## Source
#Originally posted to https://community.progress.com/s/question/0D54Q0000819ux2SAA/restart-windows-computer-powershell by Mike Rockwell
# This uses the credential assigned to the machine and the PowerShell restart is set to force. 
# Because if anyone is logged in without the -force, the script will stop.

#Get the device information
$ip = $Context.GetProperty("Address");
$DnsEntry = [System.Net.DNS]::GetHostByAddress($ip);
$DnsName = [string]$DnsEntry.HostName;
 
# Get the Windows credentials
$WinUser = $Context.GetProperty("CredWindows:DomainAndUserid");
$WinPass = $Context.GetProperty("CredWindows:Password");
$pwd = convertto-securestring $WinPass -asplaintext -force;
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $WinUser,$pwd;
 
if(Restart-Computer -ComputerName $DnsName -Credential $cred -Force)
{
	$Context.SetResult(1,"Failed to restart %Device.DisplayName");
}
else
{
	$Context.SetResult(0, "%Device.DisplayName was successfully restarted");
}