# ---- Config ----
$PrtgServer = '192.168.74.104'
$WugServer  = '192.168.74.74'
$WugProtocol = 'https'
$IgnoreSslErrors = $true  # set $false if you want strict SSL

# ---- Install modules if required & import them
try {
    if (-not (Get-Module -ListAvailable -Name 'PrtgAPI')) {Install-Module PrtgAPI -Scope CurrentUser -Force -AllowClobber}
    Import-Module PrtgAPI -ErrorAction Stop
    if (-not (Get-Module -ListAvailable -Name 'WhatsUpGoldPS')) {Install-Module WhatsUpGoldPS -Scope CurrentUser -Force -AllowClobber}
    Import-Module WhatsUpGoldPS -ErrorAction Stop
}
catch {
    throw "Module install/import failed: $($_.Exception.Message)"
}

# ---- Credentials ----
if (-not $PRTGCred) { $PRTGCred = Get-Credential -Message "Enter PRTG username and password" }
if (-not $WUGCred)  { $WUGCred  = Get-Credential -Message "Enter WhatsUp Gold username and password" }

# ---- Connect to PRTG and collect IPs/Hostnames ----
try {
    if ($IgnoreSslErrors) {
        Connect-PrtgServer -Server $PrtgServer -Credential $PRTGCred -IgnoreSSL -Force | Out-Null
    } else {
        Connect-PrtgServer -Server $PrtgServer -Credential $PRTGCred -Force | Out-Null
    }

    $devices = Get-Device
    if (-not $devices) { throw "No devices returned from PRTG." }

    $ipList = $devices |
        Where-Object { $_.Host -and $_.Host.Trim() } |
        ForEach-Object { $_.Host.Trim() } |
        Sort-Object -Unique

    if (-not $ipList -or $ipList.Count -eq 0) { throw "No usable Host values found on PRTG devices." }
}
catch {
    throw "PRTG step failed: $($_.Exception.Message)"
}

# ---- Connect to WhatsUp Gold and add devices ----
try {
    if ($IgnoreSslErrors) {
        Connect-WUGServer -serverUri $WugServer -Protocol $WugProtocol -IgnoreSSLErrors -Credential $WUGCred | Out-Null
    } else {
        Connect-WUGServer -serverUri $WugServer -Protocol $WugProtocol -Credential $WUGCred | Out-Null
    }

    Add-WUGDevice -IpOrName $ipList
    Write-Host "Added/submitted $($ipList.Count) targets to WhatsUp Gold."
}
catch {
    throw "WUG step failed: $($_.Exception.Message)"
}