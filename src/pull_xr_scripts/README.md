# pull_xr_scripts

Pulls the XR glasses scripts off every collector into a local `output/`
tree.

## Why this exists

Each `collectors` host keeps its XR-glasses Python scripts in a fixed
location, `C:\Users\User\Desktop\xreal_glasses_scripts` (flat, no
subdirectories to recurse into). This playbook copies those `*.py` files
back to the control node so they can be inspected or diffed without RDP'ing
into each collector by hand.

Every `collectors` host is only reachable through the jump host via
`ProxyJump`, and each `ansible.builtin.fetch` is its own SSH connection
through that relay — fine for one file, but the per-connection overhead
dominates once there's more than a handful of scripts. So this playbook
tars the whole directory on the host first and fetches that single
archive, rather than fetching each `*.py` file individually. Windows
10/11 ship `tar.exe` (bsdtar) out of the box, so no extra tooling needs
installing on the host to build it — but per
[deploy_tool_everything/README.md](../deploy_tool_everything/README.md),
plain `ansible.builtin` modules (`copy`, `command`) don't reliably work
against these hosts over plain SSH + `ansible_shell_type: powershell`, so
the tar itself is created with `ansible.windows.win_shell`, not
`ansible.builtin.command`. `ansible.builtin.fetch` itself is fine here
even though it's a builtin module — its action plugin dispatches to
`ansible.windows`'s own `slurp.ps1` for a Windows target, which runs
through the same PowerShell module wrapper as `win_shell` rather than the
wrapper that crashes.

## Files

- [playbook.yaml](playbook.yaml) — targets `collectors`; on each host,
  runs `tar -cf ... *.py` in the remote scripts directory
  (`ansible.windows.win_shell`), fetches that one archive back
  (`ansible.builtin.fetch`), then extracts it locally
  (`ansible.builtin.unarchive`, `delegate_to: localhost`) into
  `output/xreal_glasses_scripts/<hostname>/` at the repo root, cleaning up
  the remote and local staged archive files afterwards.

## Usage

```bash
uv run ansible-galaxy collection install -r requirements.yml  # one-time, if not already done
uv run ansible-playbook -i src/inventory.yaml src/pull_xr_scripts/playbook.yaml
```

Results land in `output/xreal_glasses_scripts/<hostname>/` (gitignored, one
directory per collector).
