# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Dependencies and the venv are managed with `uv` (Python >= 3.11).

```bash
uv sync                                                                     # install deps
uv run ansible-playbook -i src/inventory.yaml src/hello_world/playbook.yaml # run the playbook via the Ansible CLI
uv run python src/hello_world/main.py                                       # run scripts via ansible_runner and collect output
```

There is no lint/test suite in this repo currently.

## Architecture

This is a sandbox for running local scripts on a remote host via Ansible's
`script` module, through two different entry points that hit the same
target:

- **`src/inventory.yaml`** — the shared inventory. Both the playbook and
  `main.py` read this file; all playbooks now live under `src/`, one
  directory below it.
- **`src/hello_world/playbook.yaml`** — the declarative path: ping the
  host, then run `test.py` with `ansible.builtin.script`, registering and
  printing its stdout via `debug`. Driven with `ansible-playbook`.
- **`src/hello_world/main.py`** — the programmatic path: calls `ansible_runner.run()`
  ad-hoc (module `script`, no playbook file involved) per script, and parses
  the run's event stream (`runner_on_ok`/`runner_on_failed`, reading
  `event_data.res`) into `ScriptResult(host, script, rc, stdout, stderr)`
  objects collected in a `RunReport`. `RunReport.search(pattern)`
  regex-searches collected stdout across all results — the intended hook
  for scanning real script output for known patterns.

Two non-obvious constraints baked into `main.py`, needed if extending it:
- `ansible_runner` requires **absolute paths** for both the inventory and
  the script being run (it executes from inside its own private data dir,
  so relative paths silently resolve to nothing) — handled via
  `PROJECT_DIR.resolve()`.
- A script with no shebang (e.g. `test.py`) must have its interpreter
  passed explicitly, e.g. `executables={"test.py": "python3"}`, otherwise
  the remote shell tries to execute it directly and fails.

`.runner/` is `ansible_runner`'s private data directory (job artifacts,
fact cache) — gitignored, safe to delete between runs.

`compose.yml` optionally starts a Semaphore UI (port 3000) for
browsing/running these playbooks; unrelated to the Python/Ansible CLI paths
above.
