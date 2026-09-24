# Removes each path passed as an argument from Windows Defender's exclusion
# list, skipping any not currently excluded, and prints the ones actually
# removed as a JSON array ([] when none were present).
#
# Environment variables in a path (e.g. %USERPROFILE%\Desktop\logs) are
# expanded here, in the connecting user's session, the same way
# add_exclusion_path.ps1 expands them before adding, so the same input
# line matches what was added.
#
# Matching is case-insensitive (-contains), like Windows paths; the entries
# are removed using their stored spelling so Remove-MpPreference matches
# them exactly. Needs an elevated session, same as reading exclusions.

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$existing = @((Get-MpPreference).ExclusionPath | Where-Object { $_ })
$wanted = @($args | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
$present = @($existing | Where-Object { $wanted -contains $_ })

if ($present.Count -gt 0) {
    Remove-MpPreference -ExclusionPath $present
}

ConvertTo-Json -InputObject $present -Compress
