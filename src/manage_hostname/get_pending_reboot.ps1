# Reports why this host needs a reboot as a JSON array of reason names,
# e.g. ["CBS","ComputerNameChange"], or [] when nothing is pending.
#
# ComputerNameChange is the one a win_hostname rename leaves behind: the new
# name is written to ComputerName but ActiveComputerName only follows after a
# reboot.
#
# Built via -InputObject (not the pipeline) so ConvertTo-Json always emits an
# array, even for zero or one reason.

$ProgressPreference = 'SilentlyContinue'

$reasons = @()

if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $reasons += 'CBS'
}
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $reasons += 'WindowsUpdate'
}
if (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) {
    $reasons += 'PendingFileRename'
}

$nameKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName'
$active = (Get-ItemProperty "$nameKey\ActiveComputerName").ComputerName
$pending = (Get-ItemProperty "$nameKey\ComputerName").ComputerName
if ($active -ne $pending) {
    $reasons += 'ComputerNameChange'
}

ConvertTo-Json -InputObject $reasons -Compress
