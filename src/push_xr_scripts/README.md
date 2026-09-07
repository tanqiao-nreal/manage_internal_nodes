# push_xr_scripts

Pushes a local set of XR glasses scripts out to every collector, replacing
what's there - the counterpart to
[pull_xr_scripts](../pull_xr_scripts/README.md).

## Why this exists

`pull_xr_scripts` gets scripts off a collector for inspection; this is for
the other direction - rolling out an updated set of `*.py` scripts to
`C:\Users\User\Desktop\xreal_glasses_scripts` on every `collectors` host
from a single local source of truth
([input/xreal_glasses_scripts/](../../input/xreal_glasses_scripts/)).

Same transfer-cost reasoning as `pull_xr_scripts`: every `collectors` host
is only reachable through the jump host via `ProxyJump`, so the scripts are
tarred locally once and pushed as a single archive
(`ansible.windows.win_copy`) instead of copying each file individually.
`ansible.builtin.copy`/`command` are unreliable against these hosts (see
[deploy_tool_everything/README.md](../deploy_tool_everything/README.md)),
so all remote-side work (staging the archive, listing/moving/extracting)
goes through `ansible.windows` modules instead.

Before anything is overwritten, whatever's already in
`xreal_glasses_scripts` is moved (not copied) into a timestamped backup
subdirectory right there on the host - nothing is fetched back to the
control node. `existing_scripts.matched == 0` (a fresh host with nothing
deployed yet) skips that move rather than erroring on no matching files.

## Files

- [playbook.yaml](playbook.yaml) — targets `collectors`. Per run: builds
  one archive from
  [input/xreal_glasses_scripts/](../../input/xreal_glasses_scripts/)
  (`tar`, `delegate_to: localhost`, `run_once: true`) and pushes it to
  every host (`ansible.windows.win_copy`); then, per host, moves any
  existing `*.py` scripts into
  `xreal_glasses_scripts\backup\<timestamp>\` on the host
  (`ansible.windows.win_shell`, `Move-Item`); then extracts the pushed
  archive into the now-empty scripts directory; finally removes the pushed
  archive from both the host and the control node.

## Usage

Place the scripts to deploy in `input/xreal_glasses_scripts/` (gitignored,
create it if it doesn't exist), then:

```bash
uv run ansible-galaxy collection install -r requirements.yml  # one-time, if not already done
uv run ansible-playbook -i src/inventory.yaml src/push_xr_scripts/playbook.yaml
```

Each host's prior scripts land in
`C:\Users\User\Desktop\xreal_glasses_scripts\backup\<timestamp>\` before
being replaced, timestamped per run so repeated pushes don't overwrite
each other's backups. `win_find`'s non-recursive listing means an
accumulating `backup\` directory is never itself swept up and re-backed-up
on a later run.
