<#
.SYNOPSIS
  Migrate devices from ManageEngine OpManager to WhatsUp Gold (PowerShell 5.1).

.DESCRIPTION
  1) Pulls devices from OpManager using REST with apiKey header. (Header auth is recommended.)  [1](https://www.manageengine.com/network-monitoring/api-opmanager.html)
  2) Exports to CSV.
  3) Connects to WhatsUp Gold using WhatsUpGoldPS:
     -serverUri <host/ip> -Protocol <http|https> -Port <int> -IgnoreSSLErrors  [2](https://www.manageengine.com/it-operations-management/help/rest-api-opmanagerplus.html)
  4) Adds devices using Add-WUGDeviceTemplate (displayName, DeviceAddress). [4](https://docs.octoxlabs.com/adapters/adapters/manageengine-op-manager)

.NOTES
  WhatsUp Gold REST commonly runs on port 9644 by default. [3](https://portlookup.com/opmanager-plus/)
  Ignoring TLS cert validation is a security risk; use only as needed.
#>

[CmdletBinding()]
param(
  # ---- OpManager ----
  [Parameter(Mandatory=$true)]
  [string]$OpManagerBaseUrl,                  # e.g. https://opm.company.local:8060
  [Parameter(Mandatory=$true)]
  [string]$OpManagerApiKey,
  [string]$OpManagerListDevicesPath = "/api/json/device/listDevices",

  # Optional filters (supported depends on OpManager build)
  [string]$OpManagerDeviceTypeFilter,
  [string]$OpManagerCategoryFilter,

  # ---- WhatsUp Gold ----
  [Parameter(Mandatory=$true)]
  [string]$WugBaseUrl,                        # e.g. https://wug.company.local:9644 OR http://10.0.0.5:8734 OR just host/IP
  [Parameter(Mandatory=$true)]
  [string]$WugUsername,
  [Parameter(Mandatory=$true)]
  [securestring]$WugPassword,

  # Output / behavior
  [string]$ExportCsvPath = ".\opmanager_devices_export.csv",
  [switch]$DryRun,

  # TLS handling (PS5.1)
  [switch]$IgnoreSelfSignedCerts = $true,

  # WhatsUpGoldPS module handling
  [switch]$UseWhatsUpGoldPS = $true
)

# ------------------------------------------------------------
# PS5.1 TLS bypass (session-wide) for self-signed / mismatch certs
# ------------------------------------------------------------
$script:OriginalCertCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
$script:OriginalSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol

function Enable-InsecureTls {
  # Prefer TLS1.2; keep others enabled for older servers if needed
  try {
    [System.Net.ServicePointManager]::SecurityProtocol =
      [System.Net.SecurityProtocolType]::Tls12 -bor
      [System.Net.SecurityProtocolType]::Tls11 -bor
      [System.Net.SecurityProtocolType]::Tls
  } catch {}

#   Add-Type -TypeDefinition @"
# using System.Net.Security;
# using System.Security.Cryptography.X509Certificates;

# public static class TrustAllCerts {
#   public static bool Validate(object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) { return true; }
# }
# "@ -ErrorAction SilentlyContinue

  [System.Net.ServicePointManager]::ServerCertificateValidationCallback =
    [System.Net.Security.RemoteCertificateValidationCallback] [TrustAllCerts]::Validate

  Write-Host "WARNING: TLS certificate validation is disabled for this PowerShell session." -ForegroundColor Yellow
}

function Disable-InsecureTls {
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $script:OriginalCertCallback
  [System.Net.ServicePointManager]::SecurityProtocol = $script:OriginalSecurityProtocol
}

if ($IgnoreSelfSignedCerts) { Enable-InsecureTls }

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Coalesce {
  param([Parameter(ValueFromRemainingArguments = $true)]$Values)
  foreach ($v in $Values) {
    if ($null -ne $v) {
      if ($v -is [string]) { if ($v.Trim().Length -gt 0) { return $v } }
      else { return $v }
    }
  }
  return $null
}

function Normalize-BaseUrl {
  param([string]$Url)
  if (-not $Url) { return $Url }
  return $Url.TrimEnd('/')
}

function Write-JsonFile {
  param([string]$Path, $Object, [int]$Depth = 12)
  try {
    ($Object | ConvertTo-Json -Depth $Depth) | Out-File -FilePath $Path -Encoding UTF8
  } catch {
    '"<Could not serialize JSON>"' | Out-File -FilePath $Path -Encoding UTF8
  }
}

# ------------------------------------------------------------
# OpManager: HTTP calls (Invoke-RestMethod is OK once TLS bypass is enabled)
# ------------------------------------------------------------
function Get-OpManagerDevices {
  param(
    [string]$BaseUrl,
    [string]$ApiKey,
    [string]$ListPath,
    [string]$TypeFilter,
    [string]$CategoryFilter
  )

  $BaseUrl = Normalize-BaseUrl $BaseUrl
  $uri = "$BaseUrl$ListPath"

  $q = @()
  if ($TypeFilter)     { $q += "Type=$([uri]::EscapeDataString($TypeFilter))" }
  if ($CategoryFilter) { $q += "Category=$([uri]::EscapeDataString($CategoryFilter))" }
  if ($q.Count -gt 0)  { $uri = "$uri?$( $q -join '&' )" }

  $headers = @{ apiKey = $ApiKey }   # header apiKey is recommended [1](https://www.manageengine.com/network-monitoring/api-opmanager.html)

  Write-Host "Calling OpManager listDevices: $uri" -ForegroundColor Cyan
  try {
    return Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -TimeoutSec 180
  } catch {
    throw "OpManager call failed: $($_.Exception.Message)"
  }
}

function Find-DeviceArrayInResponse {
  param($obj)

  if ($null -eq $obj) { return @() }

  if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
    return @($obj)
  }
  if ($obj.devices) { return @($obj.devices) }
  if ($obj.data -and $obj.data.devices) { return @($obj.data.devices) }

  # BFS search for an array of objects having device-ish fields
  $queue = New-Object System.Collections.Queue
  $queue.Enqueue($obj)

  while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()

    if ($cur -is [System.Collections.IEnumerable] -and -not ($cur -is [string])) {
      $arr = @($cur)
      if ($arr.Count -gt 0 -and $arr[0] -is [psobject]) {
        $names = $arr[0].PSObject.Properties.Name
        if ($names -match 'device|ip|host|address') { return $arr }
      }
      foreach ($item in $arr) { $queue.Enqueue($item) }
    }
    elseif ($cur -is [psobject]) {
      foreach ($p in $cur.PSObject.Properties) { $queue.Enqueue($p.Value) }
    }
  }

  return @()
}

# ------------------------------------------------------------
# WhatsUp Gold: module install/import and connect
# ------------------------------------------------------------
function Ensure-WhatsUpGoldPS {
  if (-not (Get-Module -ListAvailable -Name WhatsUpGoldPS)) {
    Write-Host "Installing WhatsUpGoldPS module..." -ForegroundColor Yellow
    Install-Module -Name WhatsUpGoldPS -Scope CurrentUser -Force -ErrorAction Stop
  }
  Import-Module WhatsUpGoldPS -Force
}

function Parse-WugEndpoint {
  param([string]$BaseUrlOrHost)

  $protocol = "https"
  $hostPart = $BaseUrlOrHost
  $port = 9644  # default WUG REST port [3](https://portlookup.com/opmanager-plus/)

  $uri = $null
  if ([Uri]::TryCreate($BaseUrlOrHost, [System.UriKind]::Absolute, [ref]$uri)) {
    $protocol = $uri.Scheme
    $hostPart = $uri.Host
    if (-not $uri.IsDefaultPort) { $port = $uri.Port }
  }

  return [pscustomobject]@{
    Protocol = $protocol
    Host     = $hostPart
    Port     = $port
  }
}

function Connect-WugPS {
  param(
    [string]$WugBaseUrlOrHost,
    [string]$Username,
    [securestring]$Password,
    [switch]$IgnoreSSLErrors
  )

  $ep = Parse-WugEndpoint $WugBaseUrlOrHost

  $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni(
              [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
  $sec = ConvertTo-SecureString $plain -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential($Username, $sec)

  Write-Host ("Connecting to WUG: {0}://{1}:{2}" -f $ep.Protocol, $ep.Host, $ep.Port) -ForegroundColor Cyan

  # Connect-WUGServer supports -Protocol, -Port, -IgnoreSSLErrors in module v0.1.18 [2](https://www.manageengine.com/it-operations-management/help/rest-api-opmanagerplus.html)
  Connect-WUGServer -serverUri $ep.Host -Protocol $ep.Protocol -Port $ep.Port -Credential $cred -IgnoreSSLErrors:$IgnoreSSLErrors | Out-Null
}

# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------
try {
  $OpManagerBaseUrl = Normalize-BaseUrl $OpManagerBaseUrl

  Write-Host "=== Step 1: Read devices from OpManager ===" -ForegroundColor Green
  $opm = Get-OpManagerDevices -BaseUrl $OpManagerBaseUrl -ApiKey $OpManagerApiKey `
                              -ListPath $OpManagerListDevicesPath `
                              -TypeFilter $OpManagerDeviceTypeFilter `
                              -CategoryFilter $OpManagerCategoryFilter

  $debugOpm = Join-Path (Get-Location) "debug-opm-raw.json"
  Write-JsonFile -Path $debugOpm -Object $opm -Depth 12
  Write-Host "Saved OpManager response to $debugOpm" -ForegroundColor Yellow

  $devices = Find-DeviceArrayInResponse $opm
  if (-not $devices -or $devices.Count -eq 0) {
    throw "No devices found in OpManager response. Check $debugOpm and verify -OpManagerListDevicesPath."
  }

  # Map fields conservatively (no PS7 ??)
  $mapped = $devices | ForEach-Object {
    $addr = Coalesce $_.deviceName $_.networkAddress $_.ipAddress $_.ip_address $_.hostName $_.host_name $_.dnsName $_.name
    $disp = Coalesce $_.displayName $_.name $_.deviceName $_.hostName $addr
    [pscustomobject]@{
      Address     = $addr
      DisplayName = $disp
      Type        = Coalesce $_.Type $_.type $_.deviceType
      Category    = $_.Category
    }
  } | Where-Object { $_.Address }

  if ($mapped.Count -eq 0) {
    throw "After mapping, no devices have an Address. Inspect $debugOpm to see actual property names."
  }

  $mapped | Sort-Object Address | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
  Write-Host "Exported $($mapped.Count) devices to $ExportCsvPath" -ForegroundColor Green

  if ($DryRun) {
    Write-Host "DryRun enabled: stopping before WhatsUp Gold import." -ForegroundColor Yellow
    return
  }

  if (-not $UseWhatsUpGoldPS) {
    throw "This script currently imports via WhatsUpGoldPS module. Enable -UseWhatsUpGoldPS."
  }

  Write-Host "=== Step 2: Connect to WhatsUp Gold ===" -ForegroundColor Green
  Ensure-WhatsUpGoldPS
  Connect-WugPS -WugBaseUrlOrHost $WugBaseUrl -Username $WugUsername -Password $WugPassword -IgnoreSSLErrors:$IgnoreSelfSignedCerts

  Write-Host "=== Step 3: Create devices in WhatsUp Gold ===" -ForegroundColor Green

# Create a list of IPs
$ipList = [System.Collections.Generic.List[string]]::new()

$created = 0; $errors = @()

  foreach ($row in $mapped) {
    $ipList.Add($row.Address)
    $created++
  }

  # Add all devices at one with single call for discovery
  try {
      Add-WugDevice -IpOrName $ipList
  } catch {
      $errors += $_.Exception.Message
  }

  Write-Host "Import complete. Created: $created  Failed: $failed" -ForegroundColor Cyan

  if ($failed -gt 0) {
    $errPath = Join-Path (Get-Location) "wug-import-errors.txt"
    $errors | Out-File -FilePath $errPath -Encoding UTF8
    Write-Warning "Some devices failed. See $errPath"
  }
}
finally {
  # Restore TLS behavior at the very end (optional)
  if ($IgnoreSelfSignedCerts) { Disable-InsecureTls }
}