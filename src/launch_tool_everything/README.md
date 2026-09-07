# launch_tool_everything

Launches [voidtools Everything](https://www.voidtools.com/) on every host in
`managed`, if its GUI instance isn't already running.

## Why this exists

[deploy_tool_everything/](../deploy_tool_everything/) already launches
Everything as part of installing/configuring it, but that's a one-shot check
done at deploy time. Someone can close the Everything window by hand
afterwards (its headless `-svc` companion process keeps running regardless,
so this isn't obvious from the process list alone), which silently kills the
HTTP API that [everything_proxy/](../everything_proxy/) depends on. This
playbook is the standalone fix for that: run it any time to recheck and
relaunch, without repeating the install/copy/firewall steps.
[deploy_tool_everything/playbook.yaml](../deploy_tool_everything/playbook.yaml)
also runs it itself, as its last play (via `import_playbook`), so a normal
deploy still ends with Everything running.

## A caveat on "launch Everything"

`EVERYTHING_SERVICE=1` always keeps a headless `Everything.exe -svc`
running, but that instance doesn't serve the HTTP API — only a normal
(non-`-svc`) instance does. So the playbook checks for an `Everything.exe`
process whose command line *doesn't* contain `-svc` (via `Get-CimInstance
Win32_Process`, filtered on `CommandLine`) before deciding whether to
launch.

A process launched directly over SSH (`Start-Process`) has two problems,
both confirmed against a real host: it lands in Session 0, invisible to
whoever's logged in interactively, *and* it gets killed the moment the SSH
connection closes — Win32-OpenSSH ties every child process to a Job Object
scoped to that connection, which is torn down (along with everything under
it) as soon as the connection ends.

The playbook instead runs it via a `community.windows.win_scheduled_task`
with no `username`/`logon_type` set, which defaults to running under the
current interactive token — i.e. whichever session the target user is
actually logged into. Task Scheduler is an independent service, so the
process it starts is neither tied to the SSH job (survives disconnect) nor
stuck in Session 0. Confirmed against a real host: the launched process
lands in the logged-in user's session and keeps running after the SSH
connection closes.

The task's action passes `-startup`, which — confirmed against a real host
— launches Everything with no main window at all (`MainWindowHandle` is
zero, not just hidden/minimized) while still showing its tray icon and
loading the HTTP plugin normally. Without it, a relaunch pops the search
window in front of whatever the logged-in user is doing.

The task is (re)created fresh on every launch (deleted first, if it
already exists, then recreated) rather than left alone when unchanged —
otherwise the second run of this pattern is a no-op from
`win_scheduled_task`'s point of view, and there'd be nothing to actually
start. It's started with an explicit `Start-ScheduledTask` call rather
than a `registration` trigger (fires once, immediately, on creation) —
that looked like the natural way to avoid a separate "run now" step, but
turned out to be unreliable: confirmed on a real host where the task was
created successfully (correct action, correct user) yet Task Scheduler's
own history showed it had never actually run, while `Start-ScheduledTask`
against that same task worked immediately. The step still runs
best-effort (`failed_when: false`) since `START_ON_STARTUP` already
guarantees Everything will be running and visible the next time someone
logs into the host regardless.

## Usage

```bash
uv run ansible-galaxy collection install -r requirements.yml  # one-time
uv run ansible-playbook -i inventory.yaml launch_tool_everything/playbook.yaml
```

Re-running when Everything is already running (GUI instance) is a no-op —
all four tasks after the initial check report `skipped`.
