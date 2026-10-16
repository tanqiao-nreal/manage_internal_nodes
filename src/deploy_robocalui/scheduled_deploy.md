# Scheduling a deploy with `systemd-run --user`

How to run [deploy_exe.yaml](deploy_exe.yaml) unattended at a fixed time (e.g.
23:00, after everyone has stopped using robocalui) from this control
machine. Nothing extra needs installing: Ansible has no scheduler of its
own, `at` isn't installed here, but `systemd-run` ships with systemd.
Used for the v1.3.6 rollout on 2026-09-23, which ran cleanly at 23:00.

## What `systemd-run --user` does

`systemd-run` creates a *transient* unit, one that exists only in memory,
with no `.service`/`.timer` file written to disk. With `--on-calendar`, it
creates two units:

- `<name>.timer`, which waits until the given time, then
- `<name>.service`, which runs the command once and is then discarded.

`--user` puts both under your own per-user systemd instance (`systemd
--user`) instead of the system one, so no `sudo` is needed and the command
runs as you, with your `~/.ssh` keys and `~/.ssh/config`.

## Schedule it

From the repo root:

```bash
systemd-run --user \
  --unit=deploy-robocalui \
  --on-calendar='2026-09-23 23:00:00' \
  --working-directory=/home/tq/workspace/python/ansible_test \
  /home/tq/.local/bin/uv run ansible-playbook -i src/inventory.yaml src/deploy_robocalui/deploy_exe.yaml
```

- `--unit`: the name used by every command below. Pick a new one if a
  unit with that name still exists.
- `--on-calendar`: **include the full date.** A bare time like `23:00`
  normalizes to `*-*-* 23:00:00` (every day), so the deploy would run
  again every night until the timer is stopped. Check an expression before
  using it:

  ```bash
  systemd-analyze calendar '2026-09-23 23:00'   # shows "Normalized form" and "Next elapse"
  ```

  For "N from now", use `--on-active=2h` (or `30min`, etc.) instead of
  `--on-calendar`.
- `--working-directory` and the **absolute** `uv` path: the service
  doesn't run in your shell, so it has neither your current directory nor
  your shell's `PATH`.

Do a quick test run before scheduling, e.g. append `--limit compute_1` to
the command and run it directly (no `systemd-run`), so problems show up
while you're still around.

## Check, cancel, read the result

```bash
systemctl --user list-timers deploy-robocalui.timer   # queued? when does it fire?
systemctl --user stop deploy-robocalui.timer          # cancel before it fires
journalctl --user -u deploy-robocalui.service         # full playbook output, during or after the run
journalctl --user -u deploy-robocalui.service -f      # follow it live
```

Once the run finishes, the transient units are removed, so `systemctl
--user status deploy-robocalui.service` reports "could not be found".
That's expected: the output is still in the journal. Look for the
`PLAY RECAP` near the end and check `failed=0 unreachable=0` for every
host.

## What has to hold until it fires

The timer only lives in the memory of your user's systemd instance, so:

- **Stay logged in, or enable linger.** By default (`Linger=no`), your
  user's systemd instance stops when your last session ends (desktop, SSH
  or terminal logins), and any pending timer is lost with it. Locking the
  screen or turning off the monitor is fine; logging out is not. To let it
  survive logout, enable linger *before* logging out:

  ```bash
  loginctl show-user tq -p Linger     # check
  sudo loginctl enable-linger tq      # user systemd now starts at boot and outlives logout
  sudo loginctl disable-linger tq     # revert
  ```

- **Don't reboot.** Transient units don't survive a reboot, even with
  linger on. Schedule it again after a reboot.
- **Don't suspend.** On AC power this machine's idle action is `nothing`
  (`gsettings get org.gnome.settings-daemon.plugins.power
  sleep-inactive-ac-type`), so it won't go to sleep by itself, but don't
  suspend it manually.
- **SSH must work without prompts.** Nobody is there to type a
  passphrase. `~/.ssh/id_ed25519` has none, so the bastion jump and host
  logins work as-is. If the key ever gets a passphrase, the unattended
  run will fail to connect.

Also keep only the one intended `robocalui_*.exe` in
[input/robocalui/](../../input/robocalui/) until the run is done. The
playbook fails if it finds more than one.
