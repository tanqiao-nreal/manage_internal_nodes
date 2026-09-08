# Moves a single file to the Recycle Bin (not a permanent delete), given
# its full path as the first argument.
#
# Not Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(...,
# SendToRecycleBin) - confirmed against a real host that it silently
# performs a *permanent* delete instead when run this way (non-interactive
# PowerShell over SSH has no desktop session for the Shell API's recycle
# machinery to attach to). Shell.Application's InvokeVerb('delete') - the
# same call Explorer's own "Delete" context-menu entry makes - was
# confirmed against that same host to recycle correctly in this exact
# non-interactive context. 'delete' is the canonical (English) verb name,
# recognized regardless of the OS's display language.
#
# InvokeVerb doesn't report success/failure itself and there's no
# documented guarantee it has finished before returning, so this polls for
# the file to actually disappear and throws (rather than reporting a false
# success) if it's still there after a few seconds.

param(
    [Parameter(Mandatory)]
    [string]$Path
)

$folder = Split-Path -Path $Path -Parent
$filename = Split-Path -Path $Path -Leaf

$shell = New-Object -ComObject Shell.Application
$item = $shell.Namespace($folder).ParseName($filename)
if (-not $item) {
    throw "File not found via Shell namespace: $Path"
}
$item.InvokeVerb('delete')

for ($i = 0; $i -lt 10; $i++) {
    if (-not (Test-Path -Path $Path)) {
        exit 0
    }
    Start-Sleep -Milliseconds 500
}
throw "File still present after InvokeVerb('delete'): $Path"
