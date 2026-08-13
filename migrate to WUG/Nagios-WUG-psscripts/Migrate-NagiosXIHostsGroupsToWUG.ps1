<#
.SYNOPSIS
    Migrates Nagios XI hosts and host groups into Progress WhatsUp Gold (WUG).

.DESCRIPTION
    Reads hosts and host groups from the Nagios XI REST API, creates matching static device groups in WhatsUp Gold,
    adds devices using Jason Alberino's WhatsUpGoldPS module, and assigns devices to groups.

    Designed as a practical migration starter script, not a full Nagios configuration converter.
    It intentionally focuses on host and group onboarding. Service checks, contacts, escalations, notification logic,
    plugins, dependencies, and downtime schedules should be handled separately.

.REQUIREMENTS
    - PowerShell 5.1+ recommended by WhatsUpGoldPS.
    - WhatsUpGoldPS module installed:
        Install-Module WhatsUpGoldPS
    - Nagios XI API key with permission to read objects.
    - WhatsUp Gold user with REST API permissions.

.NOTES
    Author: Draft generated for Jirka Knapek
    WUG Module: WhatsUpGoldPS by Jason Alberino
    Tested assumptions:
      - Nagios XI object API endpoints are available under /nagiosxi/api/v1/objects/host and /objects/hostgroup.
      - WhatsUpGoldPS exposes Connect-WUGServer, Add-WUGDevice, Get-WUGDevice, Get-WUGDeviceGroup,
        Add-WUGDeviceGroup, and Set-WUGDeviceGroupMembership.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$NagiosBaseUrl,

    [Parameter(Mandatory=$true)]
    [string]$NagiosApiKey,

    [Parameter(Mandatory=$true)]
    [string]$WugServerUri,

    [Parameter(Mandatory=$true)]
    [System.Management.Automation.PSCredential]$WugCredential,

    [int]$WugParentGroupId = 0,

    [string]$WugGroupPrefix = "Nagios XI - ",

    [switch]$SkipCertificateCheck,

    [switch]$AllowInsecureHttp,

    [switch]$ExportOnly,

    [switch]$ForceAddDevices,

    [switch]$UseAllWugCredentials,

    [Alias('WugCredentialNames')]
    [string[]]$WugDiscoveryProfileNames,

    [string]$OutputDirectory = ".",

    [ValidateRange(5,300)]
    [int]$ApiTimeoutSec = 30,

    [ValidateRange(0,5)]
    [int]$ApiRetryCount = 2
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Output "`n=== $Message ==="
}

function Get-NormalizedBaseUrl {
    param([string]$Url)
    return $Url.TrimEnd('/')
}

function Assert-SecureUri {
    param(
        [Parameter(Mandatory=$true)][string]$UriString,
        [Parameter(Mandatory=$true)][string]$Label,
        [switch]$AllowHttp
    )

    $parsed = [System.Uri]$UriString
    if (-not $AllowHttp -and $parsed.Scheme -ne 'https') {
        throw "$Label must use HTTPS. Use -AllowInsecureHttp only for controlled non-production scenarios."
    }

    return $parsed
}

function Get-NagiosObjectUri {
    param(
        [Parameter(Mandatory=$true)][string]$BaseUrl,
        [Parameter(Mandatory=$true)][string]$ObjectType
    )

    return "$BaseUrl/nagiosxi/api/v1/objects/$([System.Uri]::EscapeDataString($ObjectType))?pretty=1"
}

function Get-RedactedUri {
    param([Parameter(Mandatory=$true)][string]$Uri)

    return ($Uri -replace '(?i)(apikey=)[^&]+', '$1***REDACTED***')
}

function Test-IsExpectedNotFound {
    param([Parameter(Mandatory=$true)]$Exception)

    if ($null -eq $Exception) { return $false }
    $msg = "$($Exception.Message)"
    return ($msg -match '(?i)\b404\b' -or $msg -match '(?i)not\s*found')
}

function Test-IsAuthFailure {
    param([Parameter(Mandatory=$true)]$Exception)

    $msg = "$($Exception.Message)"
    return ($msg -match '(?i)\b(401|403)\b' -or $msg -match '(?i)\bunauthorized\b' -or $msg -match '(?i)\bforbidden\b')
}

function Add-ApiKeyToQueryIfMissing {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$ApiKey
    )

    if ($Uri -match '(?i)(?:\?|&)apikey=') { return $Uri }
    $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
    return "$Uri${separator}apikey=$([System.Uri]::EscapeDataString($ApiKey))"
}

function Test-ApiKeyMissingInResponse {
    param($Response)

    if ($null -eq $Response) { return $false }
    if (-not ($Response.PSObject.Properties.Name -contains 'error')) { return $false }
    return "$($Response.error)" -match '(?i)no\s*api\s*key\s*provided'
}

function Get-WindowsPowerShellSecurityProtocol {
    $proto = [System.Net.SecurityProtocolType]0
    foreach ($name in @('Tls12','Tls11','Tls')) {
        if ([System.Enum]::GetNames([System.Net.SecurityProtocolType]) -contains $name) {
            $proto = $proto -bor ([System.Net.SecurityProtocolType]::$name)
        }
    }
    return $proto
}

function Invoke-JsonGetHttpWebRequest {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = 30,
        [switch]$SkipCert
    )

    $previousProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    $targetProtocol = Get-WindowsPowerShellSecurityProtocol
    if ($targetProtocol -ne [System.Net.SecurityProtocolType]0) {
        [System.Net.ServicePointManager]::SecurityProtocol = $targetProtocol
    }

    $previousCallback = $null
    if ($SkipCert) {
        $previousCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    try {
        $request = [System.Net.HttpWebRequest]::Create($Uri)
        $request.Method = 'GET'
        $request.Timeout = $TimeoutSec * 1000
        $request.ReadWriteTimeout = $TimeoutSec * 1000
        $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        foreach ($key in $Headers.Keys) {
            $request.Headers[$key] = "$($Headers[$key])"
        }

        $response = $request.GetResponse()
        try {
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            try {
                $content = $reader.ReadToEnd()
            } finally {
                $reader.Close()
            }
        } finally {
            $response.Close()
        }

        if ([string]::IsNullOrWhiteSpace($content)) { return $null }
        return ($content | ConvertFrom-Json)
    } finally {
        if ($SkipCert) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCallback
        }
        [System.Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}

function Protect-CsvValue {
    param($Value)

    if ($null -eq $Value) { return $null }
    $text = "$Value"
    if ($text -match '^[=\+\-@]') { return "'$text" }
    return $text
}

function Invoke-ApiGetJson {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [switch]$SkipCert,
        [string]$ApiKey,
        [int]$TimeoutSec = 30,
        [int]$RetryCount = 2
    )

    $safeUriForLogs = Get-RedactedUri -Uri $Uri
    Write-Verbose "GET $safeUriForLogs"

    $invokeRequest = {
        param([string]$RequestUri, [hashtable]$Headers)

        if ($PSVersionTable.PSVersion.Major -lt 7) {
            return Invoke-JsonGetHttpWebRequest -Uri $RequestUri -Headers $Headers -TimeoutSec $TimeoutSec -SkipCert:$SkipCert
        }

        if ($SkipCert -and $PSVersionTable.PSVersion.Major -ge 7) {
            return Invoke-RestMethod -Method Get -Uri $RequestUri -Headers $Headers -SkipCertificateCheck -TimeoutSec $TimeoutSec
        }

        if ($SkipCert) {
            $previousCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            try {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                return Invoke-RestMethod -Method Get -Uri $RequestUri -Headers $Headers -TimeoutSec $TimeoutSec
            } finally {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCallback
            }
        }

        return Invoke-RestMethod -Method Get -Uri $RequestUri -Headers $Headers -TimeoutSec $TimeoutSec
    }

    for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
        try {
            $requestUri = $Uri
            $headers = @{}
            if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
                $headers['apikey'] = $ApiKey
            }
            $response = & $invokeRequest -RequestUri $requestUri -Headers $headers

            if (-not [string]::IsNullOrWhiteSpace($ApiKey) -and (Test-ApiKeyMissingInResponse -Response $response)) {
                $fallbackUri = Add-ApiKeyToQueryIfMissing -Uri $Uri -ApiKey $ApiKey
                $safeFallbackForLogs = Get-RedactedUri -Uri $fallbackUri
                Write-Warning "API did not accept API key header. Falling back to query authentication for compatibility: $safeFallbackForLogs"
                return & $invokeRequest -RequestUri $fallbackUri -Headers @{}
            }

            return $response
        } catch {
            if (-not [string]::IsNullOrWhiteSpace($ApiKey) -and (Test-IsAuthFailure -Exception $_.Exception)) {
                $fallbackUri = Add-ApiKeyToQueryIfMissing -Uri $Uri -ApiKey $ApiKey
                $safeFallbackForLogs = Get-RedactedUri -Uri $fallbackUri
                Write-Warning "API header authentication failed. Falling back to query authentication for compatibility: $safeFallbackForLogs"
                return & $invokeRequest -RequestUri $fallbackUri -Headers @{}
            }

            if ($attempt -ge $RetryCount) { throw }
            Start-Sleep -Seconds ([Math]::Min(8, [Math]::Pow(2, $attempt + 1)))
        }
    }
}

function Get-ObjectArray {
    param($Response, [string[]]$LikelyNames)

    if ($null -eq $Response) { return @() }
    if ($Response -is [System.Array]) { return @($Response) }

    foreach ($name in $LikelyNames) {
        if ($Response.PSObject.Properties.Name -contains $name) {
            $value = $Response.$name
            if ($null -ne $value) { return @($value) }
        }
    }

    if ($Response.PSObject.Properties.Name -contains 'data') {
        return @(Get-ObjectArray -Response $Response.data -LikelyNames $LikelyNames)
    }

    return @($Response)
}

function Split-NagiosList {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | Where-Object { $_ } | ForEach-Object { "$($_)".Trim() }) }

    $s = "$Value".Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return @() }

    return @($s -split '\s*,\s*|\s*;\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}

function Get-FirstPropertyValue {
    param($Object, [string[]]$Names)

    foreach ($name in $Names) {
        if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $name) {
            $value = $Object.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace("$value")) {
                return "$value".Trim()
            }
        }
    }
    return $null
}

function Convert-NagiosHost {
    param($HostObjects)

    foreach ($h in $HostObjects) {
        $name = Get-FirstPropertyValue -Object $h -Names @('host_name','name','display_name')
        $address = Get-FirstPropertyValue -Object $h -Names @('address','ip_address','host_address')
        $alias = Get-FirstPropertyValue -Object $h -Names @('alias','display_name','description')
        $hostGroups = @()

        foreach ($p in @('hostgroups','hostgroup','hostgroup_name','groups')) {
            if ($h.PSObject.Properties.Name -contains $p) {
                $hostGroups += Split-NagiosList $h.$p
            }
        }

        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ([string]::IsNullOrWhiteSpace($address)) { $address = $name }

        [pscustomobject]@{
            HostName    = $name
            Address     = $address
            Alias       = $alias
            HostGroups  = @($hostGroups | Sort-Object -Unique)
            Source      = 'NagiosXI'
        }
    }
}

function Convert-NagiosHostGroup {
    param(
        $HostGroupObjects,
        [string]$GroupPrefix
    )

    foreach ($g in $HostGroupObjects) {
        $name = Get-FirstPropertyValue -Object $g -Names @('hostgroup_name','name','display_name')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $alias = Get-FirstPropertyValue -Object $g -Names @('alias','description')
        $members = @()
        foreach ($p in @('members','hostgroup_members','host_members')) {
            if ($g.PSObject.Properties.Name -contains $p) {
                $members += Split-NagiosList $g.$p
            }
        }

        [pscustomobject]@{
            HostGroupName = $name
            Description   = $alias
            Members       = @($members | Sort-Object -Unique)
            WugGroupName  = "$GroupPrefix$name"
        }
    }
}

function Get-WugObjectId {
    param($Object)

    foreach ($p in @('id','Id','deviceId','DeviceId','groupId','GroupId')) {
        if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $p) {
            $v = $Object.$p
            if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace("$v")) { return "$v" }
        }
    }
    return $null
}

function Find-WugDeviceByAddressOrName {
    param([string]$Address, [string]$Name)

    $candidates = @()
    foreach ($search in @($Address, $Name | Where-Object { $_ })) {
        try {
            $result = Get-WUGDevice -SearchValue $search -ErrorAction Stop
            if ($result) { $candidates += @($result) }
        } catch {
            if (Test-IsExpectedNotFound -Exception $_.Exception) {
                Write-Verbose "Get-WUGDevice did not find '$search'."
                continue
            }
            throw
        }
    }

    $exact = @($candidates | Where-Object {
        $props = $_.PSObject.Properties.Name
        ($props -contains 'address' -and "$($_.address)" -eq $Address) -or
        ($props -contains 'ipAddress' -and "$($_.ipAddress)" -eq $Address) -or
        ($props -contains 'networkAddress' -and "$($_.networkAddress)" -eq $Address) -or
        ($props -contains 'name' -and "$($_.name)" -eq $Name) -or
        ($props -contains 'displayName' -and "$($_.displayName)" -eq $Name)
    } | Select-Object -First 1)

    if ($exact.Count -gt 0) { return $exact[0] }
    return $null
}

function Resolve-WugDeviceGroup {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$Name,
        [string]$Description,
        [int]$ParentGroupId
    )

    $existing = $null
    try {
        $groups = Get-WUGDeviceGroup -SearchValue $Name -GroupType static_group -View detail -ErrorAction Stop
        $existing = @($groups | Where-Object {
            ($_.PSObject.Properties.Name -contains 'name' -and $_.name -eq $Name) -or
            ($_.PSObject.Properties.Name -contains 'displayName' -and $_.displayName -eq $Name)
        } | Select-Object -First 1)
    } catch {
        if (Test-IsExpectedNotFound -Exception $_.Exception) {
            Write-Verbose "Get-WUGDeviceGroup did not find '$Name'."
        } else {
            throw
        }
    }

    if ($existing) { return $existing }

    if ($PSCmdlet.ShouldProcess($Name, 'Create WUG device group')) {
        return Add-WUGDeviceGroup -ParentGroupId $ParentGroupId -Name $Name -Description $Description
    }
}

function Add-OrFind-WugDevice {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [pscustomobject]$HostRecord,
        [bool]$UseAllCredentials,
        [string[]]$DiscoveryProfiles,
        [switch]$ForceAdd
    )

    $existing = Find-WugDeviceByAddressOrName -Address $HostRecord.Address -Name $HostRecord.HostName
    if ($existing) { return $existing }

    $params = @{
        IpOrName = @($HostRecord.Address)
        UseAllCredentials = $UseAllCredentials
    }

    if ($DiscoveryProfiles -and $DiscoveryProfiles.Count -gt 0) { $params.Credentials = $DiscoveryProfiles }
    if ($ForceAdd) { $params.ForceAdd = $true; $params.ForceCreate = $true }

    if ($PSCmdlet.ShouldProcess($HostRecord.Address, 'Add device to WUG')) {
        $addResult = Add-WUGDevice @params
        Start-Sleep -Seconds 2
        $found = Find-WugDeviceByAddressOrName -Address $HostRecord.Address -Name $HostRecord.HostName
        if ($found) { return $found }
        if ($addResult) { return $addResult }
    }

    return $null
}

function Add-DeviceToWugGroup {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$DeviceId, [string]$GroupId)

    if ([string]::IsNullOrWhiteSpace($DeviceId) -or [string]::IsNullOrWhiteSpace($GroupId)) { return }

    $body = @{ groupId = "$GroupId" } | ConvertTo-Json -Depth 5
    if ($PSCmdlet.ShouldProcess("DeviceId=$DeviceId GroupId=$GroupId", 'Assign WUG group membership')) {
        Set-WUGDeviceGroupMembership -DeviceId $DeviceId -Body $body | Out-Null
    }
}

# Main
$NagiosBaseUrl = Get-NormalizedBaseUrl $NagiosBaseUrl
if (-not (Test-Path $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }

[void](Assert-SecureUri -UriString $NagiosBaseUrl -Label 'NagiosBaseUrl' -AllowHttp:$AllowInsecureHttp)
[void](Assert-SecureUri -UriString $WugServerUri -Label 'WugServerUri' -AllowHttp:$AllowInsecureHttp)

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$hostsCsv = Join-Path $OutputDirectory "nagios-xi-hosts-$timestamp.csv"
$groupsCsv = Join-Path $OutputDirectory "nagios-xi-hostgroups-$timestamp.csv"
$logCsv = Join-Path $OutputDirectory "nagios-to-wug-migration-log-$timestamp.csv"

Write-Step "Read hosts and host groups from Nagios XI"
$hostUri = Get-NagiosObjectUri -BaseUrl $NagiosBaseUrl -ObjectType 'host'
$hostGroupUri = Get-NagiosObjectUri -BaseUrl $NagiosBaseUrl -ObjectType 'hostgroup'

$rawHosts = Invoke-ApiGetJson -Uri $hostUri -ApiKey $NagiosApiKey -SkipCert:$SkipCertificateCheck -TimeoutSec $ApiTimeoutSec -RetryCount $ApiRetryCount
$rawGroups = Invoke-ApiGetJson -Uri $hostGroupUri -ApiKey $NagiosApiKey -SkipCert:$SkipCertificateCheck -TimeoutSec $ApiTimeoutSec -RetryCount $ApiRetryCount

$hosts = @(Convert-NagiosHost -HostObjects (Get-ObjectArray -Response $rawHosts -LikelyNames @('host','hosts','objects')))
$groups = @(Convert-NagiosHostGroup -HostGroupObjects (Get-ObjectArray -Response $rawGroups -LikelyNames @('hostgroup','hostgroups','objects')) -GroupPrefix $WugGroupPrefix)

# Backfill host group membership from group member list where hosts do not expose hostgroups directly.
$hostByName = @{}
foreach ($h in $hosts) { $hostByName[$h.HostName] = $h }
foreach ($g in $groups) {
    foreach ($member in $g.Members) {
        if ($hostByName.ContainsKey($member)) {
            $hostByName[$member].HostGroups = @($hostByName[$member].HostGroups + $g.HostGroupName | Sort-Object -Unique)
        }
    }
}

$hosts | Select-Object `
    @{n='HostName';e={ Protect-CsvValue $_.HostName }},
    @{n='Address';e={ Protect-CsvValue $_.Address }},
    @{n='Alias';e={ Protect-CsvValue $_.Alias }},
    @{n='HostGroups';e={ Protect-CsvValue ($_.HostGroups -join ';') }} | Export-Csv -NoTypeInformation -Path $hostsCsv

$groups | Select-Object `
    @{n='HostGroupName';e={ Protect-CsvValue $_.HostGroupName }},
    @{n='Description';e={ Protect-CsvValue $_.Description }},
    @{n='WugGroupName';e={ Protect-CsvValue $_.WugGroupName }},
    @{n='Members';e={ Protect-CsvValue ($_.Members -join ';') }} | Export-Csv -NoTypeInformation -Path $groupsCsv

Write-Output "Exported hosts:      $hostsCsv"
Write-Output "Exported hostgroups: $groupsCsv"
Write-Output "Host count:          $($hosts.Count)"
Write-Output "Host group count:    $($groups.Count)"

if ($ExportOnly) {
    Write-Output "ExportOnly specified. No WUG changes were made."
    return
}

Write-Step "Connect to WhatsUp Gold"
Import-Module WhatsUpGoldPS -ErrorAction Stop

$wugServerHost = $WugServerUri
$wugProtocol = $null
$wugPort = $null
try {
    $wugUri = [System.Uri]$WugServerUri
    if ($wugUri -and $wugUri.IsAbsoluteUri) {
        $wugServerHost = $wugUri.Host
        $wugProtocol = $wugUri.Scheme
        if (-not $wugUri.IsDefaultPort) { $wugPort = $wugUri.Port }
    }
} catch {
    # Keep raw value; module may accept hostname/IP directly.
}

$connectParams = @{
    serverUri = $wugServerHost
    Credential = $WugCredential
}
$connectCommand = Get-Command Connect-WUGServer -ErrorAction Stop
if (-not [string]::IsNullOrWhiteSpace($wugProtocol) -and $connectCommand.Parameters.ContainsKey('Protocol')) {
    $connectParams.Protocol = $wugProtocol
}
if ($null -ne $wugPort -and $connectCommand.Parameters.ContainsKey('Port')) {
    $connectParams.Port = $wugPort
}
if ($SkipCertificateCheck) {
    if ($connectCommand.Parameters.ContainsKey('IgnoreSSLErrors')) {
        $connectParams.IgnoreSSLErrors = $true
    } elseif ($connectCommand.Parameters.ContainsKey('IgnoreCertificateErrors')) {
        $connectParams.IgnoreCertificateErrors = $true
    } elseif ($connectCommand.Parameters.ContainsKey('SkipCertificateCheck')) {
        $connectParams.SkipCertificateCheck = $true
    } else {
        Write-Warning "SkipCertificateCheck was requested, but Connect-WUGServer does not expose a certificate-skip parameter in this WhatsUpGoldPS version."
    }
}
Connect-WUGServer @connectParams | Out-Null

foreach ($cmd in @('Add-WUGDevice','Get-WUGDevice','Get-WUGDeviceGroup','Add-WUGDeviceGroup','Set-WUGDeviceGroupMembership')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "Required WhatsUpGoldPS command '$cmd' is not available. Update the WhatsUpGoldPS module and try again."
    }
}

Write-Step "Create or resolve WUG device groups"
$groupIdByName = @{}
foreach ($g in $groups) {
    $wugGroup = Resolve-WugDeviceGroup -Name $g.WugGroupName -Description "Migrated from Nagios XI hostgroup '$($g.HostGroupName)'" -ParentGroupId $WugParentGroupId
    $groupId = Get-WugObjectId $wugGroup
    if ($groupId) {
        $groupIdByName[$g.HostGroupName] = $groupId
        Write-Output "Group OK: $($g.HostGroupName) -> $($g.WugGroupName) [$groupId]"
    } else {
        Write-Warning "Could not determine WUG group ID for '$($g.WugGroupName)'. Device membership for this group may be skipped."
    }
}

Write-Step "Add devices and assign group membership"
$log = New-Object System.Collections.Generic.List[object]

foreach ($h in $hosts) {
    $status = 'Unknown'
    $deviceId = $null
    $message = $null

    try {
        $device = Add-OrFind-WugDevice -HostRecord $h -UseAllCredentials:$UseAllWugCredentials -DiscoveryProfiles $WugDiscoveryProfileNames -ForceAdd:$ForceAddDevices
        $deviceId = Get-WugObjectId $device

        if (-not $deviceId) {
            throw "Device was added or found, but returned object did not include an ID."
        }

        foreach ($hg in $h.HostGroups) {
            if ($groupIdByName.ContainsKey($hg)) {
                Add-DeviceToWugGroup -DeviceId $deviceId -GroupId $groupIdByName[$hg]
            } else {
                Write-Warning "Host '$($h.HostName)' references hostgroup '$hg', but no matching WUG group ID was found."
            }
        }

        $status = 'Success'
        $message = 'Device processed and group membership attempted.'
        Write-Output "OK: $($h.HostName) [$($h.Address)] -> DeviceId=$deviceId"
    } catch {
        $status = 'Failed'
        $message = "$($_.Exception.Message)"
        Write-Warning "FAILED: $($h.HostName) [$($h.Address)] - $message"
    }

    $log.Add([pscustomobject]@{
        HostName = $h.HostName
        Address = $h.Address
        HostGroups = ($h.HostGroups -join ';')
        WugDeviceId = $deviceId
        Status = $status
        Message = $message
    })
}

$log | Select-Object `
    @{n='HostName';e={ Protect-CsvValue $_.HostName }},
    @{n='Address';e={ Protect-CsvValue $_.Address }},
    @{n='HostGroups';e={ Protect-CsvValue $_.HostGroups }},
    @{n='WugDeviceId';e={ Protect-CsvValue $_.WugDeviceId }},
    Status,
    @{n='Message';e={ Protect-CsvValue $_.Message }} | Export-Csv -NoTypeInformation -Path $logCsv
Write-Step "Done"
Write-Output "Migration log: $logCsv"
Disconnect-WUGServer | Out-Null
