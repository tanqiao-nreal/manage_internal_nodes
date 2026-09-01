# Reports every fixed disk (DriveType=3) as a JSON array:
# [{"DeviceID": "C:", "TotalBytes": ..., "FreeBytes": ...}, ...]
#
# Built via -InputObject (not the pipeline) so ConvertTo-Json always emits
# an array, even for zero or one disk - piping a single object through
# ConvertTo-Json collapses it to a bare JSON object instead of a 1-item array.

$ProgressPreference = 'SilentlyContinue'

$disks = @(
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' |
        Select-Object DeviceID, @{N='TotalBytes'; E={[int64]$_.Size}}, @{N='FreeBytes'; E={[int64]$_.FreeSpace}}
)

ConvertTo-Json -InputObject $disks -Compress
