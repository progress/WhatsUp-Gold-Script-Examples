#Process CPU usage
#This active monitor polls a target system for $ProcessName and calculates the current CPU usage of the process

# Note: This example is provided as an illustration only and is not supported.
# Technical support is available for the Context object, SNMP API, and scripting environment, 
# but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
# For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
# or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

#Name of the process to get CPU Utilization information about
$ProcessName = "Idle";
#Labled the monitor down is CPU usage is greater than...
$Threshold = 5;
# Get servername
$ip = $Context.GetProperty("Address");
$DnsEntry = [System.Net.DNS]::GetHostByAddress($ip)
$DnsName = [string]$DnsEntry.HostName;
$bProcessFound = 0
# Get the Windows credentials
$WinUser = $Context.GetProperty("CredWindows:DomainAndUserid");
$WinPass = $Context.GetProperty("CredWindows:Password");
$pwd = convertto-securestring $WinPass -asplaintext -force;
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $WinUser, $pwd;
#Gather the information
$CpuCores = (Get-WmiObject Win32_ComputerSystem -ComputerName $DnsName).NumberOfLogicalProcessors;
Try {
    $Samples = (get-counter -Counter "\\$DnsName\Process($ProcessName)\% processor time" -SampleInterval 5 -MaxSamples 2 | select -ExpandProperty countersamples | select -ExpandProperty cookedvalue | Measure-Object -Average).average
    $Value = [Decimal]::Round(($Samples.CookedValue / $CpuCores), 2)
    $resultText = "The process $ProcessName has $Value% CPU usage"
}
Catch { $bProcessFound = 1 }
If ($bProcessFound -eq 0) {
    #Set up or down in WhatsUp Gold
    If ($Value -ge $Threshold){
        $Context.SetResult(1, $resultText);
    } Else { 
        $Context.SetResult(0, $resultText);
    }
} Else { 
    $Context.SetResult(0, "The process wasn't found to be running or we can't connect to the counter...")
}