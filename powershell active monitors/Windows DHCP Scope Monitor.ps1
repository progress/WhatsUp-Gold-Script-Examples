#Windows DHCP Scope Monitor
# This active monitor polls a target system for DHCP scope and calculates the percent of usage
# This will be labeled down if the percentage of usage of the DHCP scope is greater or equal to $nThresold

# Note: This example is provided as an illustration only and is not supported.
# Technical support is available for the Context object, SNMP API, and scripting environment, 
# but Progress does not provide support for JScript, VBScript, or developing and debugging Active Script monitors or actions.
# For assistance with this example or with writing your own scripts, visit the https://community.progress.com/s/code-share
# or contact our professional services team https://www.whatsupgold.com/professional-services#custom-configuration

#Percentage
$nThreshold = 99
#Get the device information
$ip = $Context.GetProperty("Address");
$bDown = 0
# Get the Windows credentials
$WinUser = $Context.GetProperty("CredWindows:DomainAndUserid");
$WinPass = $Context.GetProperty("CredWindows:Password");
$Winpwd = convertto-securestring $WinPass -asplaintext -force;
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $WinUser, $Winpwd;
#Get the scope information through WMI
$scopeInfo = (Get-WmiObject -ComputerName $ip -Namespace ROOT\Microsoft\Windows\DHCP -List -Credential $cred | Where-Object Name -eq 'PS_DhcpServerv4ScopeStatistics').Get() | Select-Object -ExpandProperty cmdletOutput | Where-Object { $_.PercentageInUse -ge $nThreshold } | Select-Object ScopeId, AddressesInUse, AddressesFree, PercentageInUse
if (!$scopeInfo) {
    $bDown = 0
    $sMsg = "All scopes have <$nThreshold% addresses in use"
}
else {
    $bDown = 1
    foreach ($scope in $scopeInfo) {
        $scopeId = $scope.ScopeId
        $scopeAddressesFree = $scope.AddressesFree
        $scopePercentageInUse = $scope.PercentageInUse
        $scopePercentageInUse = [math]::Round($scopePercentageInUse, 2)
        $sMsg += "${scopeId} has ${scopeAddressesFree} addresses free (${scopePercentageInUse}% used)`r`n"
    }
}
# Set the active monitor result: 0 = success, 1 = failure
If ($bDown -eq 0){
    $Context.SetResult(0, "${sMsg}")
} Else { 
    $Context.SetResult(1, "One or more scopes has >${nThreshold}% addresses in use.`r`n $sMsg")
}