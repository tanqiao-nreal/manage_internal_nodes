# ansible-test

A sandbox for driving Ansible against remote hosts, both via the
`ansible-playbook` CLI and programmatically through `ansible_runner`.

## Setup

Dependencies are managed with `uv`:

```bash
uv sync
```

[inventory.yaml](inventory.yaml) defines:
- `jumphost` — `jump_admin`, the admin account (`xreal`) on the jump server
  (`10.32.9.14`) that sits in front of the managed hosts.
- `managed` — a parent group (all Windows hosts) reached through a
  restricted `bastion` relay account on the jump server via `ProxyJump`.
  `bastion` can only forward TCP (no shell, no TTY) — see the next section
  for how it and the managed hosts are kept in sync. It has two child
  groups: `collectors` and `computes`, split by role — both use the same
  connection and key-trust setup. Its group vars also set
  `ansible_shell_type: powershell`, which tells Ansible's SSH connection to
  use PowerShell syntax for the shell-level plumbing `ansible.builtin`
  modules need (remote temp dirs, etc.) — without it, modules like
  `ansible.builtin.script`/`command`/`copy` don't work against these hosts
  at all (see [disk_usage/](disk_usage/) below for a module-based playbook
  that relies on this).

## Files

- [inventory.yaml](inventory.yaml) — the `jumphost`/`managed` inventory
  described above.
- [playbook.yaml](playbook.yaml) — pings `computes` and runs [test.py](test.py)
  via the `ansible.builtin.script` module, printing its stdout. This
  currently assumes a POSIX target; see the caveat below.
- [test.bash](test.bash) / [test.py](test.py) — dummy scripts that just print
  a line of output, used to exercise the run-and-collect workflow.
- [main.py](main.py) — runs local scripts on the inventory hosts via
  `ansible_runner` (no playbook needed) and collects their output for
  programmatic use.
- [scripts/](scripts/) — small helper scripts shared across the playbooks
  below (currently just `encode_ps_command.py`).
- [bootstrap_access/](bootstrap_access/) — bootstraps SSH access through the
  jump host onto the managed hosts; see
  [bootstrap_access/README.md](bootstrap_access/README.md).
- [disk_usage/](disk_usage/) — reports fixed-disk usage across every managed
  host as an HTML page; see [disk_usage/README.md](disk_usage/README.md).

> **Caveat:** `playbook.yaml` and `main.py` predate `computes` becoming a real
> (Windows) host and still assume a POSIX target (`ansible.builtin.script`
> running a bash/python script directly). `managed` now sets
> `ansible_shell_type: powershell` (see above), which is the piece that was
> missing for `ansible.builtin` modules to work here at all — `disk_usage/`
> relies on exactly that — but `playbook.yaml` and `main.py` themselves
> haven't been adapted or tested against it, so running them against
> `compute_6` as-is still isn't expected to work.

## Running the playbook directly

```bash
uv run ansible-playbook -i inventory.yaml playbook.yaml
```

## Running scripts from Python

`main.py` uses `ansible_runner.run()` ad-hoc (module `script`) to execute a
local script on the matched hosts and parses the run's events into
`ScriptResult` objects (`host`, `script`, `rc`, `stdout`, `stderr`):

```bash
uv run python main.py
```

`run_scripts()` runs a list of scripts and returns a combined `RunReport`.
`RunReport.search(pattern)` regex-searches collected stdout across all
results, e.g. `report.search(r"error", re.IGNORECASE)`, which is meant as the
starting point for scanning real script output for known patterns.

Notes:
- Scripts without a shebang line (e.g. `test.py`) need an explicit
  interpreter, passed as `executables={"test.py": "python3"}`.
- `ansible_runner` requires absolute paths for both the inventory and the
  script being run; `main.py` resolves these relative to the project
  directory automatically.
- `.runner/` is `ansible_runner`'s private data directory (job artifacts,
  fact cache) — it's gitignored and safe to delete between runs.

## Semaphore (optional)

[compose.yml](compose.yml) starts a [Semaphore](https://semaphoreui.com/) UI
for browsing/running these playbooks, on port 3000:

```bash
docker compose up -d
```
