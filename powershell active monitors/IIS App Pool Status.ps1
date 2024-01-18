#IIS App Pool Status
# This active monitor polls all IIS application pools on a target system and is labeled down
# if any app pools are not equal to 'Running'

# Note: This example is provided as an illustration only and is not supported.
# Technical support is available for the Context object, SNMP API, and scripting environment, 
# but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
# For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
# or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

$resultText = ""
$failureResult = ""
#Get the device information
$ip = $Context.GetProperty("Address");
$DnsEntry = [System.Net.DNS]::GetHostByAddress($ip)
$DnsName = [string]$DnsEntry.HostName;
$bDown = 0
# Get the Windows credentials
$WinUser = $Context.GetProperty("CredWindows:DomainAndUserid");
$WinPass = $Context.GetProperty("CredWindows:Password");
$pwd = convertto-securestring $WinPass -asplaintext -force;
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $WinUser, $pwd;
#Gather the information
$appPools = (Get-WmiObject Win32_PerfFormattedData_APPPOOLCountersProvider_APPPOOLWAS -Filter "Name != '_Total'" -Credential $cred -ComputerName $DnsName)
foreach ($app in $appPools) {
    $appPool = $app.Name
    $appPoolState = $app.CurrentApplicationPoolState

    if ($appPoolState -ne 3) {
        $bDown = 1
        $failureResult = $failureResult + "$appPool is not running `r`n"
    }

    if ($appPoolState -eq 1) { $appPoolState = "Uninitialized" }
    if ($appPoolState -eq 2) { $appPoolState = "Initialized" }
    if ($appPoolState -eq 3) { $appPoolState = "Running" }
    if ($appPoolState -eq 4) { $appPoolState = "Disabling" }
    if ($appPoolState -eq 5) { $appPoolState = "Disabled" }
    if ($appPoolState -eq 6) { $appPoolState = "Shutdown Pending" }
    if ($appPoolState -eq 7) { $appPoolState = "Delete Pending" }
    $resultText = $resultText + "$appPool is $appPoolState `r`n"
    [System.GC]::Collect()
}

# Set the active monitor result: 0 = success, 1 = failure
If ($bDown -eq 0){
    $Context.SetResult(0, $resultText);
} Else { 
    $Context.SetResult(1, $failureResult);
}