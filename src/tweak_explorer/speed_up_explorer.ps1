# Stops Explorer from stalling on folders with many files, for the
# connecting user, and prints what it did as a single JSON object:
# {"Changed": ["FolderType", "IconsOnly"], "ExplorerRestarted": false}
#
# - FolderType: Explorer normally samples a folder's files and, if it looks
#   like music/video/pictures, switches to a template whose columns
#   (Length, Bitrate, Dimensions...) make it open every file to read its
#   metadata. FolderType=NotSpecified on the AllFolders bag turns that
#   guessing off, so every folder opens as "General items". Folders already
#   seen keep their guessed type in their own saved bag, so the first time
#   this is applied, all saved folder views (Bags/BagMRU) are wiped too -
#   which also resets per-folder sort order, view mode and window size.
# - IconsOnly: "Always show icons, never thumbnails".
#
# Both live in HKCU: OpenSSH loads the connecting user's own hive, so this
# changes that user's Explorer, which is only the desktop user's if they're
# the same account. Already-applied settings are left alone, so rerunning
# is a no-op ("Changed": []).
#
# Explorer only picks this up fully after a restart. -RestartExplorer kills
# this user's explorer.exe when something changed; Winlogon starts the
# shell again on its own (other apps keep running, open Explorer windows
# close).

param([switch]$RestartExplorer)

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$shellKey = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell'
$allFoldersKey = "$shellKey\Bags\AllFolders\Shell"
$advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

function Get-RegValue($Key, $Name) {
    (Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue).$Name
}

function Set-RegValue($Key, $Name, $Value, $Type) {
    if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
    New-ItemProperty -Path $Key -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

$changed = @()

if ((Get-RegValue $allFoldersKey 'FolderType') -ne 'NotSpecified') {
    # Wipe before setting: AllFolders itself lives under Bags.
    foreach ($key in "$shellKey\Bags", "$shellKey\BagMRU") {
        if (Test-Path $key) { Remove-Item -Path $key -Recurse -Force }
    }
    Set-RegValue $allFoldersKey 'FolderType' 'NotSpecified' String
    $changed += 'FolderType'
}

if ((Get-RegValue $advancedKey 'IconsOnly') -ne 1) {
    Set-RegValue $advancedKey 'IconsOnly' 1 DWord
    $changed += 'IconsOnly'
}

$restarted = $false
if ($RestartExplorer -and $changed.Count -gt 0) {
    # Only this user's shell: an admin session could otherwise see and kill
    # other signed-in users' explorer.exe too. The name comes from the
    # session's token: over OpenSSH $env:USERDOMAIN is "WORKGROUP", not the
    # computer name Get-Process reports as the owner's domain.
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $explorers = @(Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
        Where-Object { $_.UserName -eq $me })
    if ($explorers.Count -gt 0) {
        $explorers | Stop-Process -Force
        $restarted = $true
    }
}

[pscustomobject]@{
    Changed           = @($changed)
    ExplorerRestarted = $restarted
} | ConvertTo-Json -Compress
