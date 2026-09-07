# deploy_tool_everything

Deploys [voidtools Everything](https://www.voidtools.com/) to every host in
`managed`.

## Why this exists

A one-shot install of Everything (search indexer + HTTP/ETP query servers)
across the fleet, using the project's own checked-in installer and plugin
files rather than each host's console being touched by hand.

Unlike `disk_usage/`, this needs to transfer a multi-file payload (a 4MB
MSI, three plugin DLLs, `es.exe`) to each host, not just run one script.
`ansible.builtin.copy`/`file`/`command` turned out not to work reliably
against these hosts over plain SSH + `ansible_shell_type: powershell` (a
real bug: Ansible's Python module-invocation wrapper crashes with a
PowerShell `ConvertFrom-Json` error on this connection setup — confirmed
against a real host, not assumed). The `ansible.windows` collection's
modules (`win_copy`, `win_package`, `win_shell`, `win_stat`) don't share
that wrapper and were verified working against a real host before this
playbook was built around them. The launch step additionally uses
`community.windows.win_scheduled_task` (see below) — see
[requirements.yml](../requirements.yml) for both collections.

## Files

- [resource/](resource/) — the checked-in payload: the MSI installer,
  `plugins/` (Everything's official plugin DLLs), `es.exe` (the CLI
  client), and `Plugins.ini` (plugin config — enables the HTTP server by
  default).
- [playbook.yaml](playbook.yaml) — checks each host for an existing
  install (`C:\Program Files\Everything\Everything.exe`); if found, skips
  the copy/install steps and prints a message. Otherwise: copies the MSI
  and installs it (`ansible.windows.win_package`, silent by default), and
  copies `plugins/` and `es.exe` into the install directory. From there,
  the rest runs unconditionally on every host, install-skipped or not:
  resolving the connecting user's `%APPDATA%`, stopping Everything if it's
  running and copying `Plugins.ini` there (see below), launching
  `Everything.exe` if it isn't already running, and ensuring an inbound
  firewall allow rule for it across all profiles (Domain/Private/Public) —
  see further below for why.

## Why there's no separate "register autostart" step

The MSI's own `EVERYTHING_SERVICE` and `START_ON_STARTUP` properties both
default to `1` — installing it silently with no extra arguments already
gets you the Everything Service (headless, starts at boot) *and* the
familiar GUI app relaunching at user logon, which is exactly what an
interactive install does. No extra registration is needed.

## Config changes (e.g. the HTTP server port)

`Plugins.ini` sets the HTTP server (`http_server64.dll`) to port `50000`
instead of Everything's default `80`, since 80 isn't free on every host.
Everything only reads `Plugins.ini` at startup, and re-copying it onto an
already-running instance wouldn't take effect (or might not even be
possible — the file could be open). So before the copy, the playbook stops
any running non-`-svc` `Everything.exe` (see below for why `-svc` is
excluded); the existing "launch if not running" step further down then
relaunches it, picking up the new config. This runs on every playbook run,
not just when the config actually changed — a minor cost (a few seconds of
downtime) in exchange for staying simple.

`everything_proxy`'s Nginx config proxies to this same port
(`nginx_everything_proxy.conf.j2`'s `proxy_pass`) — the two are not
derived from one shared variable, so if this port ever changes again, that
file needs updating too.

## A caveat on "launch Everything"

`EVERYTHING_SERVICE=1` always keeps a headless `Everything.exe -svc`
running, but that instance doesn't serve the HTTP API — only a normal
(non-`-svc`) instance does. So the playbook checks for an `Everything.exe`
process whose command line *doesn't* contain `-svc` (via `Get-CimInstance
Win32_Process`, filtered on `CommandLine`) before deciding whether to
launch — this runs unconditionally, so a host that already had Everything
installed but isn't currently running it (e.g. after a reboot with no
logon yet) gets launched too, not just freshly-installed ones.

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

## Firewall

Everything's first attempt to bind its HTTP server normally triggers
Windows' interactive "allow this app to communicate on private/public
networks" prompt — nobody's there to click it on a headless host, and
until it's clicked the server is unreachable. The playbook creates a
single inbound allow rule (`-Name 'Everything'`, `-Profile Any`) covering
all three network profiles, so this never needs a click. It runs
unconditionally (not just for fresh installs) so already-deployed hosts
pick it up too. It doesn't touch any *other* pre-existing "Everything"
firewall rules a host might already have (e.g. from an interactive click
or the MSI itself) — those are simply redundant with this one, not
conflicting.

## Usage

```bash
uv run ansible-galaxy collection install -r requirements.yml  # one-time
uv run ansible-playbook -i inventory.yaml deploy_tool_everything/playbook.yaml
```
