# Installs the exact set of public keys piped on stdin (one per line)
# into administrators_authorized_keys, replacing its previous contents,
# and re-applies the strict ACL that Windows OpenSSH requires for
# accounts in the Administrators group (SYSTEM + Administrators only;
# anything else and sshd rejects the file).
#
# The caller supplies the complete desired set (the project's checked-in
# authorized_keys file plus the jump admin's own key) - this replaces
# rather than merges, so anything else already in the file is removed.
#
# Idempotency is signalled purely via exit code, not text output: the
# target's console locale may not be UTF-8 (see the caller), so stdout
# can't be safely decoded. Exit 0 = already up to date, exit 77 = the
# file was updated, anything else = a real error.

$ErrorActionPreference = 'Stop'
# Non-interactive PowerShell over SSH has no host to render progress
# records against, so cmdlets that trigger one (e.g. first-use module
# auto-load) serialize it as CLIXML on stderr instead. Silencing it
# avoids that noise being mistaken for an actual error.
$ProgressPreference = 'SilentlyContinue'
$path = 'C:\ProgramData\ssh\administrators_authorized_keys'

$raw = [Console]::In.ReadToEnd() -replace "`r`n", "`n"
[string[]]$desired = $raw -split "`n" | Where-Object { $_.Trim() -ne '' } | Sort-Object -Unique
[string[]]$existing = if (Test-Path $path) { Get-Content $path } else { @() }

if (@(Compare-Object $existing $desired -SyncWindow 0).Count -eq 0) {
    exit 0
}

Set-Content -Path $path -Value $desired -Encoding ascii
icacls $path /inheritance:r | Out-Null
icacls $path /grant 'Administrators:F' | Out-Null
icacls $path /grant 'SYSTEM:F' | Out-Null
exit 77
