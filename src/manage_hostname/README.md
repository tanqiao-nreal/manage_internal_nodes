# manage_hostname

Two playbooks for tracking and fixing duplicate Windows machine names across
the `computes` group.

## Why this exists

`computes` nodes are cloned/imaged, and some end up sharing the same Windows
machine name even though each has a distinct `ansible_host` IP in
[inventory.yaml](../inventory.yaml). `get_compute_name.yaml` is the
read-only survey (what's the actual name on each box right now?);
`set_compute_name.yaml` is the write path that applies corrected names read
from a CSV.

## Files

- [get_compute_name.yaml](get_compute_name.yaml) — runs `hostname` on every
  `computes` host (`ansible.windows.win_shell`, tolerant of
  unreachable/erroring hosts) and renders the results to
  `output/compute_name/<timestamp>.csv` via
  [report.csv.j2](report.csv.j2).
- [report.csv.j2](report.csv.j2) — the CSV template: one row per host
  (`inventory_hostname, ansible_host, machine_name`), or an `ERROR: ...`
  value in `machine_name` for a host that was unreachable or failed the
  query.
- [set_compute_name.yaml](set_compute_name.yaml) — reads
  `input/compute_name/new_name.csv`, fails fast (before touching any host)
  if its `inventory_hostname` column doesn't exactly match the `computes`
  inventory group, then sets each host's machine name via
  `ansible.windows.win_hostname`. Errors on individual hosts don't stop the
  rest of the run. It does **not** reboot anything — a Windows name change
  only fully applies after a reboot, and rebooting compute nodes
  automatically was judged too risky to do unattended. The final summary
  lists which hosts were renamed and still need a manual reboot, which
  failed to rename, and which were unreachable.

## Usage

```bash
uv run ansible-galaxy collection install -r requirements.yml  # one-time, if not already done

# Survey: write output/compute_name/<timestamp>.csv
uv run ansible-playbook -i src/inventory.yaml src/manage_hostname/get_compute_name.yaml

# Edit input/compute_name/new_name.csv (inventory_hostname, new_name) to the desired names, then:
uv run ansible-playbook -i src/inventory.yaml src/manage_hostname/set_compute_name.yaml
```

`input/compute_name/new_name.csv` must have exactly one row per host in the
`computes` group — no missing hosts, no extra rows. After a successful run,
manually reboot any host the summary lists as needing one.
