# tweak_windows_defender

Two playbooks for inspecting and extending Windows Defender's exclusion
list across every host in `managed`.

## Files

- [get_defender_status.yaml](get_defender_status.yaml) — read-only. Prints,
  per host, `AMRunningMode` and `RealTimeProtectionEnabled` (from
  `Get-MpComputerStatus`) plus the current `ExclusionPath` list (from
  `Get-MpPreference`). A host where the Defender cmdlets fail (e.g.
  Defender disabled or removed) shows an `ERROR: ...` line instead of
  aborting the run.
- [get_defender_status.ps1](get_defender_status.ps1) — the query itself,
  run on each host via `ansible.builtin.script`; prints one JSON object,
  same style as [disk_usage/get_disk_usage.ps1](../disk_usage/get_disk_usage.ps1).
- [add_exclusion_path.yaml](add_exclusion_path.yaml) — reads
  `input/tweak_windows_defender/exclusion_path.txt` (one path per line;
  blank lines and `#` comments ignored; fails before touching any host if
  it has no paths), then on each host adds whichever of those paths aren't
  already excluded, via [add_exclusion_path.ps1](add_exclusion_path.ps1)
  (paths passed as script arguments). Existing exclusions are kept, never
  replaced, and the task only reports `changed` when something was
  actually added. Trailing backslashes are stripped from each path (except
  a drive root like `C:\`), since they'd garble the argument on its way
  into the script.
- [add_exclusion_path.ps1](add_exclusion_path.ps1) — adds the argument
  paths not already excluded via `Add-MpPreference` (which appends, unlike
  `Set-MpPreference`) and prints the ones it added as a JSON array.
  `%VAR%` references are expanded first, as the connecting user, so a
  per-user path like `%USERPROFILE%\Desktop\logs` resolves to each host's
  own profile even though usernames differ between hosts (see
  `inventory.yaml`).

Both need the SSH session to be elevated (an admin account): reading
exclusions as a non-admin returns an `N/A: Must be an administrator...`
placeholder, and adding them fails outright.

## Usage

```bash
# Check status and current exclusions
uv run ansible-playbook -i src/inventory.yaml src/tweak_windows_defender/get_defender_status.yaml

# Edit input/tweak_windows_defender/exclusion_path.txt, then:
uv run ansible-playbook -i src/inventory.yaml src/tweak_windows_defender/add_exclusion_path.yaml
```

Add `--limit <host_or_group>` to try it on a subset first.
