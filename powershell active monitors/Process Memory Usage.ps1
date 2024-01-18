#Process Memory usage
#This active monitor polls a target system for $ProcessName and calculates the current memory usage of the process

# Note: This example is provided as an illustration only and is not supported.
# Technical support is available for the Context object, SNMP API, and scripting environment, 
# but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
# For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
# or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

#Name of the process to get Memory Utilization information about
$ProcessName = "explorer"
#Amount of Memory utilization percentage not to be over
$Threshold = 25

# Get servername
$ip = $Context.GetProperty("Address");
$DnsEntry = [System.Net.DNS]::GetHostByAddress($ip)
$DnsName = [string]$DnsEntry.HostName;
$bProcessFound = 0
# Get the Windows credentials
$WinUser = $Context.GetProperty("CredWindows:DomainAndUserid");
$WinPass = $Context.GetProperty("CredWindows:Password");
$pwd = convertto-securestring $WinPass -asplaintext -force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $WinUser, $pwd
#Get the number of CPUs
$memory = (Get-WmiObject Win32_PhysicalMemory -ComputerName $DnsName -Credential $cred).Capacity[0]
$Capacity = $memory / 1024 / 1024
#Collect the performance count
$Counter = "\Process($ProcessName)\working set - private"
Try {
    $Data = Get-Counter $Counter -ComputerName $DnsName -SampleInterval 5 -MaxSamples 1
    #Set the value in WUG
    $RawValue = $Data.CounterSamples.CookedValue
    $KBtoMB = [math]::Round($RawValue / 1024 / 1024, 2)
    $Percentage = ($RawValue / $memory) * 100
    $PercentageValue = [math]::Round($Percentage, 2)
    $resultText = "The process $ProcessName has $KbtoMB MB physical memory usage ($PercentageValue% of $Capacity MB total capacity)"
}
Catch {
    $resultText = "Process named $ProcessName not found!"
    $bProcessFound = 1
}

# Set the active monitor result: 0 = success, 1 = failure
If ($bProcessFound = 0) {
    If ($PercentageValue -ge $Threshold){
        $Context.SetResult(1, $resultText);
    } Else { 
        $Context.SetResult(0, $resultText);
    }
} Else {
    $Context.SetResult(0, $resultText)
}