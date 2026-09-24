# Adds each path passed as an argument to Windows Defender's exclusion list,
# skipping any already excluded, and prints the ones actually added as a
# JSON array ([] when nothing was missing).
#
# Environment variables in a path (e.g. %USERPROFILE%\Desktop\logs) are
# expanded here, in the connecting user's session, before being added:
# Defender itself runs as LocalSystem, so an unexpanded %USERPROFILE% would
# resolve to the system profile rather than this user's.
#
# Add-MpPreference appends (Set-MpPreference would replace the whole list).
# -notcontains is case-insensitive, matching how Windows treats paths.
# Needs an elevated session, same as reading exclusions.

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$existing = @((Get-MpPreference).ExclusionPath | Where-Object { $_ })
$wanted = @($args | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
$missing = @($wanted | Where-Object { $existing -notcontains $_ })

if ($missing.Count -gt 0) {
    Add-MpPreference -ExclusionPath $missing
}

ConvertTo-Json -InputObject $missing -Compress
