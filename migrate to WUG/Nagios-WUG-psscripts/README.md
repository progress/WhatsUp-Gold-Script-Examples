# Nagios XI to WhatsUp Gold Migration Script

## Purpose

`Migrate-NagiosXIHostsGroupsToWUG.ps1` migrates **Nagios XI hosts and host groups** into **Progress WhatsUp Gold (WUG)**.

It is focused on onboarding inventory:
- Reads hosts and host groups from Nagios XI API
- Exports data to CSV
- Creates static WUG device groups
- Adds/resolves devices in WUG
- Assigns devices to matching WUG groups

It does **not** migrate full monitoring logic (checks, alerts, escalations, contacts, dependencies, downtime).

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- `WhatsUpGoldPS` module installed:
  ```powershell
  Install-Module WhatsUpGoldPS -Scope CurrentUser
  ```
- Nagios XI API key (read access to objects)
- WUG account with API permissions
- **Create required credentials before starting the script**:
  - A valid Nagios XI API key
  - A valid WUG user/password that can authenticate to the WUG API

## Main Parameters

| Parameter | Required | Description |
|---|---|---|
| `-NagiosBaseUrl` | Yes | Nagios XI base URL (for example `https://10.100.24.56`) |
| `-NagiosApiKey` | Yes | Nagios XI API key |
| `-WugServerUri` | Yes | WUG server URI |
| `-WugCredential` | Yes | WUG credential (`PSCredential`) |
| `-ExportOnly` | No | Export CSV only, no WUG changes |
| `-SkipCertificateCheck` | No | Skip TLS certificate validation (lab/self-signed scenarios) |
| `-AllowInsecureHttp` | No | Allow HTTP URLs (disabled by default) |
| `-WugParentGroupId` | No | Parent WUG group ID (default `0`) |
| `-WugGroupPrefix` | No | Prefix for created WUG groups (default `Nagios XI - `) |
| `-UseAllWugCredentials` | No | Use all WUG discovery credentials when adding devices |
| `-WugDiscoveryProfileNames` | No | Specific WUG discovery credential/profile names |
| `-ForceAddDevices` | No | Force add/create device behavior |
| `-OutputDirectory` | No | Output folder for CSV files/logs |
| `-ApiTimeoutSec` | No | Nagios API timeout per call (default `30`) |
| `-ApiRetryCount` | No | Retry count for Nagios API calls (default `2`) |

## Usage

### 1) Export only (no WUG changes)

```powershell
$dummy = New-Object System.Management.Automation.PSCredential(
  'unused',
  (ConvertTo-SecureString 'unused' -AsPlainText -Force)
)

.\Migrate-NagiosXIHostsGroupsToWUG.ps1 `
  -NagiosBaseUrl 'https://10.100.24.56' `
  -NagiosApiKey '<NAGIOS_API_KEY>' `
  -WugServerUri 'https://10.100.24.65' `
  -WugCredential $dummy `
  -ExportOnly `
  -SkipCertificateCheck `
  -OutputDirectory '.\output'
```

### 2) Full migration (create groups, add devices, assign memberships)

```powershell
$wugCred = Get-Credential

.\Migrate-NagiosXIHostsGroupsToWUG.ps1 `
  -NagiosBaseUrl 'https://10.100.24.56' `
  -NagiosApiKey '<NAGIOS_API_KEY>' `
  -WugServerUri 'https://10.100.24.65' `
  -WugCredential $wugCred `
  -SkipCertificateCheck `
  -OutputDirectory '.\output'
```

## Output Files

Each run creates timestamped files in `-OutputDirectory`:
- `nagios-xi-hosts-YYYYMMDD-HHMMSS.csv`
- `nagios-xi-hostgroups-YYYYMMDD-HHMMSS.csv`
- `nagios-to-wug-migration-log-YYYYMMDD-HHMMSS.csv` (full runs)

## Notes

- HTTPS is enforced by default. Use `-AllowInsecureHttp` only for controlled lab/testing.
- For some Nagios XI setups, API key header auth may be rejected; the script automatically falls back to query-key auth with redacted logging.
- If running with `-SkipCertificateCheck`, use it only where self-signed/local certificates are expected.
- **Monitoring credentials are not migrated from Nagios XI to WUG automatically.**  
  Create required WUG monitoring credentials (SNMP/WMI/SSH/API, etc.) before migration, then use:
  - `-UseAllWugCredentials`, or
  - `-WugDiscoveryProfileNames` to target specific pre-created WUG credentials/profiles.
