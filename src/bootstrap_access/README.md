# bootstrap_access

Bootstraps SSH access through the jump host onto the managed hosts.

## Why this exists

Every host in `managed` (both `collectors` and `computes`) is only
reachable through the jump server, and only trusts a specific set of SSH
public keys — on Windows, that list lives in
`C:\ProgramData\ssh\administrators_authorized_keys` (the file OpenSSH
consults for accounts in the Administrators group; per-user
`authorized_keys` is ignored for them). Getting a new person access means
updating that file on every managed host, *and* updating the `bastion`
relay account's own `authorized_keys` on the jump server — otherwise their
key would be trusted at the far end but rejected at the relay, and they'd
never get through to use it.

This subdirectory makes that a one-file edit instead of a manual, easy-to-forget
two-place change.

## Files

- [authorized_keys](authorized_keys) — the checked-in source of truth: one
  public key per line for everyone who should be able to reach the managed
  computes through the jump host.
- [playbook.yaml](playbook.yaml) — syncs that file onto `bastion`'s
  `authorized_keys` on the jump server, then pushes it (plus `jump_admin`'s
  own key) onto every host in `managed`.
- [install_keys.ps1](install_keys.ps1) — the PowerShell script actually run
  on each Windows host: replaces `administrators_authorized_keys` with the
  desired key set and re-applies the strict ACL (`SYSTEM` + `Administrators`
  only) OpenSSH requires for that file, exiting `0` if nothing changed or
  `77` if it updated the file.
- [../scripts/encode_ps_command.py](../scripts/encode_ps_command.py) —
  encodes `install_keys.ps1` as a `-EncodedCommand` base64/UTF-16LE
  payload, so it can be handed to the remote `powershell` invocation
  without fighting nested shell-quoting across bash → ssh → PowerShell.
  This is only needed here (not in `disk_usage/`) because this script also
  needs the desired key set piped into it on stdin, which rules out just
  transferring and running the file directly.
- [install_on_host.sh](install_on_host.sh) — runs on `jump_admin`; does the
  actual `ssh ... -EncodedCommand ...` call against one managed host and
  writes its output to a per-host log instead of letting Ansible capture it
  (see Usage below for why).

## Usage

To grant someone access, add their public key as a new line in
[authorized_keys](authorized_keys), then run:

```bash
uv run ansible-playbook -i inventory.yaml bootstrap_access/playbook.yaml -K
```

`-K` prompts for `xreal`'s sudo password, needed to write `bastion`'s
`authorized_keys` (owned by a different user). The playbook is idempotent —
re-running it with no changes to `authorized_keys` reports `changed=0`.

If a compute-side install ever fails, its output isn't surfaced through
Ansible (the target's console locale may not be UTF-8, which Ansible can't
safely deserialize) — instead it's logged on `jump_admin` at
`/tmp/bootstrap_access_install-<host>.log` (one file per host) for direct
inspection. The install task also retries a couple of times before failing
a host, since a first-ever connection to a host (new SSH host key, first
PowerShell invocation) has occasionally dropped mid-run without a
decodable error even though the change landed.
