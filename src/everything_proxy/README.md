# everything_proxy

Deploys a unified Nginx reverse proxy on the jump server, fronting every
managed host's [voidtools Everything](https://www.voidtools.com/) HTTP
server behind one entry point.

## Why this exists

Each managed host's Everything HTTP server (deployed by
[deploy_tool_everything/](../deploy_tool_everything/), on port `50000` —
port 80 isn't free on every host) is only reachable at
`http://<host_ip>:50000` from the host itself or the jump server — not
from outside. This puts Nginx on the jump server in front of all of them, so
`http://<jump_server_ip>/<host_name>/` reverse-proxies to that host's
Everything server (including its search API and file-download-by-path
feature — see [aggregated_everything_server.md](../aggregated_everything_server.md)
for the API details this was built to expose), and
`http://<jump_server_ip>/` lists every host (`?json=1` for JSON instead of
HTML).

## Why Jinja templates, not a Python script

The per-host proxy blocks and the host-list page are both just "loop over
`groups['managed']` and render a block per host" — the same pattern
`disk_usage/report.html.j2` already uses. The host list is static at
deploy time (not something that needs computing per-request), so the root
endpoint's `?json=1` branching is handled by pre-rendering two static files
(`index.html`, `index.json`) and having Nginx pick between them with a
plain `rewrite`/`if` — no Lua/njs module, no Python needed.

## Access control

Everything's HTTP server itself has no auth configured. Proxying it
publicly on the jump server's port 80 would mean anyone who can reach that
IP gets unauthenticated file search *and download* across every managed
host — a bigger exposure than SSH-via-bastion access. The proxy is
protected with HTTP Basic Auth (`auth_basic` + `/etc/nginx/.htpasswd`,
generated from a credential in a Vault-encrypted `vault.yml`).

## Files

- [templates/nginx_everything_proxy.conf.j2](templates/nginx_everything_proxy.conf.j2)
  — the Nginx site config: one `location /<host>/ { proxy_pass
  http://<ansible_host>:50000/; }` pair (plus a no-trailing-slash redirect)
  per host in `managed` (`50000` matches the port
  [deploy_tool_everything/resource/Plugins.ini](../deploy_tool_everything/resource/Plugins.ini)
  configures Everything's HTTP server with — the two aren't derived from a
  shared variable, so they need updating together if it ever changes), a
  `location = /` that rewrites to `index.json` when
  `$arg_json` is set or `index.html` otherwise, and `auth_basic` guarding
  the whole server block. Each per-host location also uses `sub_filter` to
  rewrite `="/` → `="/<host>/` in HTML/CSS responses — Everything emits
  root-absolute links/assets/form-actions (`href="/C%3A"`,
  `src="/Everything.gif"`, `action="/"`) with no idea it's behind a path
  prefix, so without this, clicking anything on the proxied page 404s at
  the proxy root instead of going back through `/<host>/`. Requires
  `--with-http_sub_module`, which this jump server's Nginx already has
  built in (statically, confirmed via `nginx -V`).
- [templates/index.html.j2](templates/index.html.j2) /
  [templates/index.json.j2](templates/index.json.j2) — the static
  host-list pages.
- [vault.yml.example](vault.yml.example) — plaintext reference showing the
  two expected var names. The real `vault.yml` is Vault-encrypted and safe
  to commit (see Usage).
- [playbook.yaml](playbook.yaml) — generates the htpasswd hash (via
  `openssl passwd -apr1`, fed over stdin rather than as an argument so the
  plaintext password never appears in the jump server's process list),
  renders the three files above, disables the stock `sites-enabled/default`
  site (was the only thing using port 80), enables ours, and reloads Nginx
  — but only after `nginx -t` validates the new config, and only if
  anything actually changed.

## Usage

One-time setup — create the real credential file:

```bash
uv run ansible-vault create everything_proxy/vault.yml
```

Paste in the two vars from [vault.yml.example](vault.yml.example) with real
values, then deploy:

```bash
uv run ansible-playbook -i inventory.yaml everything_proxy/playbook.yaml --ask-vault-pass -K
```

`-K` prompts for `xreal`'s sudo password (needed to write into
`/etc/nginx/`); `--ask-vault-pass` prompts for the Vault password you set
above. Re-running with no changes reports `changed=0` and doesn't reload
Nginx.

Verify: `curl -u <user>:<pass> http://10.32.9.14/` (HTML list),
`http://10.32.9.14/?json=1` (JSON list), or
`http://10.32.9.14/<host_name>/?search=<pattern>&json=1` (proxied straight
through to that host's Everything search API).
