# Reports Windows Defender's state as a single JSON object:
# {"AMRunningMode": "Normal", "RealTimeProtectionEnabled": true, "ExclusionPath": [...]}
#
# ExclusionPath is wrapped in @() so ConvertTo-Json always emits an array -
# a single exclusion would otherwise collapse to a bare string, and none to
# null. Reading exclusions needs an elevated session; a non-admin one gets
# back "N/A: Must be an administrator..." instead of the real list.

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$status = Get-MpComputerStatus

[pscustomobject]@{
    AMRunningMode             = $status.AMRunningMode
    RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
    ExclusionPath             = @((Get-MpPreference).ExclusionPath | Where-Object { $_ })
} | ConvertTo-Json -Compress
