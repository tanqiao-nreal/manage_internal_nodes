# tweak_explorer

Stops File Explorer from freezing when opening folders with many files,
across every host in `managed`.

## Why this exists

On `audio_1`, opening a folder with many files hung Explorer, and Defender
had already been ruled out (all of `C:\` was excluded). There were two
likely causes, both inside Explorer itself:

1. **Folder-type guessing.** Explorer samples a folder's files. If they look
   like audio, video or pictures, it picks the matching template, whose
   columns (Length, Bitrate, Dimensions...) make it open every file to read
   its metadata.
2. **Thumbnail generation** for every file shown.

Both can be fixed with a per-user registry setting. Folder type could also
be forced per folder with a `desktop.ini`, but that puts a hidden extra
file into data folders, where any script that lists them would see it. So
this turns the guessing off for every folder instead.

## Files

- [speed_up_explorer.yaml](speed_up_explorer.yaml) runs
  [speed_up_explorer.ps1](speed_up_explorer.ps1) on each host via
  `ansible.builtin.script`. The task reports `changed` only when a setting
  was actually changed.
- [speed_up_explorer.ps1](speed_up_explorer.ps1) sets, in `HKCU`:
  - `...\Shell\Bags\AllFolders\Shell\FolderType = NotSpecified`, which
    makes every folder open as "General items". The first time it's set,
    all saved per-folder views (`Bags`/`BagMRU`) are wiped as well, since
    folders Explorer has already seen keep their guessed type there. This
    also resets each folder's saved sort order, view mode and window size.
  - `...\Explorer\Advanced\IconsOnly = 1`, the same as "Always show icons,
    never thumbnails".

  It prints `{"Changed": [...], "ExplorerRestarted": bool}`. Settings that
  are already in place are skipped, so running it again changes nothing.

## Caveats

- **Per user.** The settings go into the hive of the SSH user
  (`ansible_user` in `inventory.yaml`). They only affect the desktop if
  people sign in to it with that same account.
- **Restart needed.** Explorer fully picks the settings up only after it
  restarts or the user signs in again. Pass `-e restart_explorer=true` to
  kill that user's `explorer.exe` on hosts where something changed.
  Winlogon restarts the shell automatically. Other apps keep running, but
  open Explorer windows close.

## Usage

```bash
# Try it on the affected host first
uv run ansible-playbook -i src/inventory.yaml src/tweak_explorer/speed_up_explorer.yaml --limit audio_1 -e restart_explorer=true

# Then everywhere (applies at next sign-in)
uv run ansible-playbook -i src/inventory.yaml src/tweak_explorer/speed_up_explorer.yaml
```
