# deploy_robocalui

Deploys `robocalui_*.exe` to the Desktop of every host in `managed`,
replacing whatever's there and (re)launching it.

## Why this exists

Rolls out an updated build of robocalui from a single local source of
truth ([input/robocalui/](../../input/robocalui/)) to every managed host,
the same shape of problem as `push_xr_scripts` but for a single GUI EXE
that also needs to be running afterwards.

## Files

- [playbook.yaml](playbook.yaml) — targets `managed`. Per run: discovers
  the one `robocalui_*.exe` staged in
  [input/robocalui/](../../input/robocalui/) (glob, not hardcoded, since
  the version in the filename changes between releases — fails loudly if
  it finds zero or more than one candidate); then, per host: resolves the
  connecting user's Desktop path dynamically (`$env:USERPROFILE`, since
  it differs between the `collectors` and `computes` groups — see
  `inventory.yaml`), and pushes the new EXE to that user's own
  `AppData\Local\Temp` *first*. Only once that copy has actually landed
  does anything disruptive happen: the running `robocalui_*` process (if
  any) is stopped, the existing `robocalui_*.exe` on the Desktop (if any)
  is reported (so it's clear what's about to be replaced) and moved to
  the Recycle Bin via [recycle_file.ps1](recycle_file.ps1), the staged
  EXE is moved from the temp location onto the Desktop, and finally it's
  (re)launched via a `community.windows.win_scheduled_task` — same
  reasoning as [launch_tool_everything](../launch_tool_everything/README.md):
  a GUI process started directly over SSH lands in the invisible Session
  0 and is killed the moment the SSH connection closes, while a Scheduled
  Task with no `username`/`logon_type` set runs under the current
  interactive token instead. If the initial push fails (network blip,
  disk full, etc.), the play aborts right there — the host is left
  exactly as it was, still running whatever it was running before.
- [recycle_file.ps1](recycle_file.ps1) — moves one file (path passed as
  its argument) to the Recycle Bin. Uses `Shell.Application`'s
  `InvokeVerb('delete')`, not
  `[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(...,
  SendToRecycleBin)` — confirmed against a real host that the latter
  silently performs a *permanent* delete instead of recycling when run
  this way (non-interactive PowerShell over SSH has no desktop session
  for the Shell API's recycle machinery to attach to). `InvokeVerb`
  doesn't report success/failure itself, so the script polls for the file
  to actually disappear and throws if it's still there after a few
  seconds, rather than reporting a false success.

## Why the temp location is the user's own `AppData\Local\Temp`, not `C:\Windows\Temp`

`Move-Item` between two paths on the same volume is a rename, which
keeps the file's existing ACL rather than making it inherit the
destination folder's. An earlier version of this playbook staged the
push under `C:\Windows\Temp` instead, whose ACL is Administrators/SYSTEM
only — confirmed against a real host that this made the scheduled task
launch step fail with Access Denied: it runs at `RunLevel: Limited` (a
UAC-filtered, non-elevated token, even for an account in the
Administrators group), which doesn't carry an enabled Administrators SID
and so got no access via that ACL. Staging under the connecting user's
own `AppData\Local\Temp` instead sidesteps this rather than working
around it: confirmed against that same host that files created there
already carry that user's own `FullControl` entry (inherited from the
profile), matching the Desktop's ACL, so the move afterward needs no
fixup.

## Usage

Place the build to deploy in `input/robocalui/` (gitignored, create it if
it doesn't exist) as `robocalui_<version>.exe`, removing any older build
that was there before — only one may be present when the playbook runs:

```bash
uv run ansible-galaxy collection install -r requirements.yml  # one-time, if not already done
uv run ansible-playbook -i src/inventory.yaml src/deploy_robocalui/playbook.yaml
```

Each host ends up with only the newly pushed EXE on its Desktop (the
previous one, if any, went to that host's Recycle Bin rather than being
deleted outright) and a running instance of it, launched via the
`RobocaluiLaunch` scheduled task.
