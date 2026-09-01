# disk_usage

Reports fixed-disk usage across every managed host as an HTML page.

## Why this exists

A simple, read-only "how full are these disks" check across every managed
host, rendered as one HTML page instead of raw Ansible output.

Unlike `bootstrap_access/`, this doesn't need to fight ssh quoting or pipe
stdin into a remote script, so it targets `managed` directly and uses plain
`ansible.builtin` modules (relying on `ansible_shell_type: powershell` on
that group — see the project README) rather than hand-rolled `ssh` calls.

## Files

- [get_disk_usage.ps1](get_disk_usage.ps1) — queries every fixed disk
  (`DriveType=3`) via `Get-CimInstance Win32_LogicalDisk` and prints a JSON
  array of `{DeviceID, TotalBytes, FreeBytes}`.
- [playbook.yaml](playbook.yaml) — two plays: the first runs
  `get_disk_usage.ps1` on every host in `managed` via
  `ansible.builtin.script` (which copies the file over and executes it — no
  `jump_admin` detour, no base64 encoding needed); the second runs on
  `localhost` and renders the report from those results via `hostvars`.
- [report.html.j2](report.html.j2) — the report template: one table per
  host with a usage bar per drive, or an error row for any host that was
  unreachable or failed the query.
- `report.html` — the generated report (gitignored; regenerated each run).

## Usage

```bash
uv run ansible-playbook -i inventory.yaml disk_usage/playbook.yaml
```

Then open `disk_usage/report.html` in a browser. A host that's unreachable
or errors out shows up as an error row rather than failing the whole run.
