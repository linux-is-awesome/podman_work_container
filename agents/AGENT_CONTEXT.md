# Work Container Context (Compact)

## Use This First
- Read this file before changes.
- Priority: current user instruction > this file > defaults.

## Project Shape
- Script-driven workflow under `scripts/{host,container,dev}/`.
- Installed runtime lives under `/usr/local/lib/work_container` (host scripts flattened into `…/scripts/`; `app-runners/` kept as a subdir; `config/` tree copied as-is).
- Main service/container name: `work_container`.
- `./start` dispatches: host cmds → `scripts/host/`, build/vpn → `scripts/dev/`.

## Script layout
- `scripts/host/` — install/uninstall, service-*, run, exec-in, host helpers, `app-runners/`, `wrappers/` (copied to `/usr/local/bin`).
- `scripts/container/` — image entrypoint pieces (`entrypoint`, `vpn-updown`, `sfdx-auth-watch`); `COPY`’d into the image.
- `scripts/dev/` — project-local only: `build`, `clear-build-cache`, `configure-vpn`.
- `scripts/host/resolve-paths` — shared `SCRIPT_DIR` / `PROJECT_DIR` / `CONFIG_DIR` for project (`scripts/host`) and installed (`…/work_container/scripts`) layouts.

## Config layout
- `config/vpn/` — `vpn.env`, `vpn.env.example`, `swanctl.conf.template`, charon-*, `gai.conf`
- `config/proxy/` — `tinyproxy.conf.template`, `proxy.env` / `proxy.env.template`
- `config/shell/` — `bashrc`, `profile` (seeded into APP_HOME)

## Non-Negotiables
- Keep **project scripts** and **installed runtime behavior** aligned.
- No new runtime dependencies unless explicitly requested.
- Use **image** terminology only (never reintroduce archive naming).
- **No backward compatibility.** Never add migration shims, dual code paths, renamed-file cleanup in install/uninstall, “support old config/layout” branches, or deprecated-option handling unless the user explicitly requests it in the current session.

## Current Important Behaviors
- Container `HOME` / `XDG_*` / `BROWSER` / `WORK_CONTAINER_HOST_HOME` are set once in `service-start` (`work_container_run_app_home_env`); all `podman exec` paths inherit them. App config lives under `~/.containers/work_container/home`. Host home is bind-mounted at the same path for projects/fonts; service start cwd is host home.
- `sf`/`sfdx`, `work-container-app`, and `exec-in` pass `--workdir "${PWD}"` so the container session follows the caller’s directory (must exist in the container, typically under the bind-mounted host home). `work-shell` does the same when `PWD` exists in the container; otherwise it falls back to `--workdir "${HOME}"` (probe via `test -d`) so the shell still opens.
- `service-status` checks running container first, then image availability.
- VPN watchdog in `scripts/container/entrypoint`: retries every 2s while unhealthy, every 10s when tunnel+DNS OK; checks CHILD_SA and DNS (`getent`), not IKE name alone; logs `VPN watchdog: network OK (tunnel and DNS working again)` plus public egress IP when recovering after a drop (not duplicated if already healthy at startup).
- IKEv2 DPD: `dpd_delay = 10s` set on the connection in `config/vpn/swanctl.conf.template` (charon default is disabled/0s); `dpd_timeout` has no effect on IKEv2 so it is not set. Child `dpd_action = restart` re-initiates the CHILD_SA under a fresh IKE_SA when DPD detects the peer is unresponsive.
- `podman build` (via `scripts/dev/build`) has no `--no-cache`/cache-busting `ARG`, so unchanged Containerfile layers (base apt incl. agent/file tools, Chrome/VS Code/Cursor/Cursor CLI/GitHub Desktop/`sf`/ngrok/mise curl+apt installs) are reused across rebuilds indefinitely — verified a rebuild reused an 8-week-old cached image byte-for-byte (same Image ID), serving stale app versions. `./start clear-build-cache` (`scripts/dev/clear-build-cache`, `sudo podman image prune -f`) clears the dangling/cache layers so the next `./start build` fetches fresh versions; normal `./start build` stays cached/fast for iterative testing. Not wired into the installed runtime bundle (build-only scripts like `build`/`configure-vpn` stay project-local under `scripts/dev/`).
- Cursor: installed in `Containerfile` from the official Anysphere apt repo (`downloads.cursor.com/aptrepo` + `downloads.cursor.com/keys/anysphere.asc`), same pattern as the VS Code repo (unpinned `apt-get install -y cursor`, so a genuinely fresh `./start build` gets latest). GUI launcher: `scripts/host/app-runners/cursor-work-open` bind-mounted on `/usr/bin/cursor` (real Anysphere `/usr/bin/cursor` symlink target is `/usr/share/cursor/bin/cursor`, a CLI/tunnel router script — must `exec /usr/share/cursor/cursor` directly, the Electron binary, not `bin/cursor`); desktop entry `Icon=co.anysphere.cursor`, `StartupWMClass=Cursor` (verified against the real `.deb`'s shipped `cursor.desktop`).
- Cursor CLI (`agent`): installed in `Containerfile` via `https://cursor.com/install` with `HOME=/opt/cursor-agent` so files land under `/opt/cursor-agent/.local/...`, then symlinked to `/usr/local/bin/agent` and `/usr/local/bin/cursor-agent` (on PATH for `work-shell` / `exec-in`). No host wrapper — run via `work-shell` (e.g. `work-shell agent`, or interactive then `agent`). Auth (`agent login` or `CURSOR_API_KEY`) and CLI state use container APP_HOME; browser login should use container Chrome (`BROWSER`) / VPN. Version updates with image rebuild (same cache caveat as other curl layers); `agent update` to image-owned `/opt` may fail for non-root — prefer rebuild.
- GitHub Desktop: installed in `Containerfile` via the mwt apt mirror of the shiftkey Linux port (`mirror.mwt.me/shiftkey-desktop`, package `github-desktop`; preferred over `apt.packages.shiftkey.dev` which failed SSL hostname checks in this env). GUI launcher: `scripts/host/app-runners/github-desktop-work-open` bind-mounted on `/usr/local/bin/github-desktop` (not `/usr/bin/github-desktop` — that symlink resolves to `/usr/lib/github-desktop/github-desktop` and a mount there overwrites the Electron binary). Runner `exec`s `/usr/lib/github-desktop/github-desktop`. Desktop `Icon=github-desktop`, `StartupWMClass=GitHub Desktop`, MIME `x-github-client` / `x-github-desktop-auth` / `x-github-desktop-dev-auth`.
- VPN DNS: `scripts/container/vpn-updown` writes `/etc/resolv.conf` from `PLUTO_DNS4_*` on CHILD up (`config/vpn/swanctl.conf.template` `updown = …`); no hardcoded resolver IPs.
- VPN path is **IPv4-only**: entrypoint disables container IPv6 (`config/vpn/gai.conf` prefers IPv4 in glibc). Bridge iface MTU set to 1400 in entrypoint/vpn-updown (`WORK_CONTAINER_IFACE_MTU`). strongSwan `kernel-netlink.mss = 1360` plus iptables `TCPMSS --clamp-mss-to-pmtu` on IPsec OUTPUT; swanctl child uses `copy_df`. No per-app network flags.
- VPN startup must not terminate the container if tunnel/DNS is down initially; watchdog keeps retrying while container/apps remain usable.
- `Public egress IP` log line is a post-connectivity curl check only, not kill-switch config.
- Logs should use plain text without `[work_container]`/`[start ...]` prefixes.
- Proxy support is Node-focused via tinyproxy on host-local port (default `3128`), configurable through `config/proxy/proxy.env`.
- Proxy template is `config/proxy/tinyproxy.conf.template`; runtime proxy config is rendered under `/etc/tinyproxy/tinyproxy.conf` (not `/tmp`).
- `service-start` and `service-status` should report real proxy status (based on host listening socket), not just configured endpoint text.
- VPN kill-switch in `scripts/container/entrypoint`: IPv4 default DROP; egress internet only via `-m policy --pol ipsec`; IKE UDP to `VPN_SERVER_IP`; TCP to bridge gateway for host dev/Chrome/ngrok backend only; INPUT TCP dport `NODE_PROXY_PORT` for published tinyproxy; `ip6tables` all DROP; mangle `TCPMSS --clamp-mss-to-pmtu` on IPsec OUTPUT only. Manual checks: `tests/verify-killswitch-features.sh` (see `tests/README.md`).
- Host → container exec: `scripts/host/host-podman-exec` — all app/tool commands use `work_container_exec_as_user` (setpriv to host uid/gid/groups). GUI launches add session env via `podman_append_gui_session_env`. Stdio: `podman_exec_stdio_args` (`-i` always; `-t` when both streams are TTYs); probes set `WORK_CONTAINER_EXEC_STDIO=probe` for `-i` only. `work-proxy` uses `podman logs` only (no exec).

- Devices: `scripts/host/host-mounts` `add_host_usb_devices` — `--privileged` and `/dev:/dev:rslave` (host hot-plug, same ACLs); `/run/udev:ro` when present (libudev add/remove for Chrome FIDO/HID after USB replug); optional host `pcscd` rundir (`/run/pcscd` or `/var/run/pcscd`) so a socket started later is visible. Wired from `service-start` and `run`. VPN kill-switch unchanged.
- GUI apps (Chrome, Firefox, VS Code, Cursor, GitHub Desktop): host desktop entries call `work-container-app <app>` (no per-app `work-*` wrappers). Desktop files under `desktop/` install to `~/.local/share/applications` with MIME handlers so they appear in host Default Applications: browsers use `Exec=… %U` + `x-scheme-handler/http(s)` / `text/html`; editors use `Exec=… %F` + `text/plain` / `inode/directory` / `application/x-code-workspace` and `TextEditor` category; GitHub Desktop uses `Exec=… %U` + `x-scheme-handler/x-github-client` / `x-github-desktop-auth` / `x-github-desktop-dev-auth`. Install does not force defaults (user picks in Settings or `xdg-settings`/`xdg-mime`). Runner passes URL/file args through; Chrome/Firefox flags come before `"$@"` so `%U` stays valid. Host paths outside the bind-mounted home may not open. Chrome: `scripts/host/app-runners/chrome-work-open` bind-mounted on `/usr/bin/google-chrome-stable` and `/usr/local/bin/google-chrome`; must `exec /opt/google/chrome/chrome` (not `google-chrome-stable`, mount target). Set `BROWSER=/usr/local/bin/chrome-work-open` in container GUI env (`exec-in`, `work-container-app`) for xdg-open / VS Code external links. VS Code: `scripts/host/app-runners/vscode-work-open` on `/usr/bin/code`; `exec /usr/share/code/code`; `StartupWMClass=code`. Cursor: `scripts/host/app-runners/cursor-work-open` on `/usr/bin/cursor`; `exec /usr/share/cursor/cursor`; `StartupWMClass=Cursor`. GitHub Desktop: `scripts/host/app-runners/github-desktop-work-open` on `/usr/local/bin/github-desktop`; `exec /usr/lib/github-desktop/github-desktop`; `StartupWMClass=GitHub Desktop`.
- Session D-Bus for portals (color picker / screencast): `service-start`/`run` set `DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus` and `XDG_SESSION_TYPE=wayland`; GUI exec always forwards the same via `podman_append_gui_session_env` so Chrome/VS Code can reach host `xdg-desktop-portal` PickColor.
- Host timezone: `work_container_host_timezone` resolves IANA zone (timedatectl, `/etc/timezone`, `/etc/localtime`); `service-start`/`run` set `TZ` and mount `/usr/share/zoneinfo/<zone>` on `/etc/localtime` (symlink bind-mount is unreliable). GUI exec passes `TZ` via `podman_append_gui_session_env` (Chrome needs `TZ`, not only `/etc/localtime`).
- `mise` is baked into the image at `/usr/local/bin/mise`. User-installed runtimes (`mise install`) persist under `~/.containers/work_container/home` (container `HOME` / `XDG_*`), not in the image layer. Default shell rc ships in `config/shell/bashrc` (includes `mise activate`) and `config/shell/profile`; `service-start` copies them into APP_HOME when `~/.bashrc` / `~/.profile` are missing. `work-shell` runs `bash -i` (normal rc files). Image also includes `pipx` (+ `python3`/`python3-venv`) for CLI apps into APP_HOME.
- Agent/file tooling in the image from Debian repos only (no compilers, no extra tool repos): `rg` (ripgrep), `fd` (symlink to Debian `fdfind`), `jq`, `yq` (Debian/`python3-yq`), `unzip`/`zip`, `file`, `rsync`, `sqlite3`, `tree`, `xxd`, `lsof`, `inotify-tools`, `libglib2.0-bin` (`gio` for xdg-open MIME on the shared session bus; not a GNOME desktop). Build toolchains and third-party CLIs (`gh`, etc.) stay out; install per project via `mise`/apt when needed.
- Host-open bridges (`scripts/host/host-open/`): extensible container→host open helpers. Convention: `bin/<handler>`; optional `applications/<handler>.desktop` + `config/xdg/mimeapps.list` (MIME/scheme); optional `bind-paths.list` lines (`<handler> <absolute-path>`) for apps that probe fixed binaries. `host-mounts` mounts every `bin/*` → `/usr/local/bin/`, every `applications/*.desktop` → `/usr/local/share/applications/`, every bind-paths entry, and mimeapps → `/etc/xdg/mimeapps.list` — no per-handler special cases in host-mounts. Do not map http(s) here (VPN Chrome via `BROWSER`). Handlers: `host-file-manager` → host `xdg-open` for `inode/directory` via `busctl` `StartTransientUnit` (container-side FileManager1 often activates Nautilus as a service with no visible window); `host-terminal` → host default terminal via `xdg-terminal-exec` (`StartTransientUnit` + `/bin/bash -c`) running host `bash -ic 'work-shell …; exec bash'` so exiting work-shell drops to host bash; probe aliases in `bind-paths.list` (`x-terminal-emulator`, `gnome-terminal`). Image includes `libglib2.0-bin` (`gio`) so in-container xdg-open’s GNOME path resolves MIME to `host-file-manager.desktop` (CLI helpers only — not a GNOME desktop).


- SF auth storm watch (`scripts/container/sfdx-auth-watch`, image `/usr/local/bin/work-container-sfdx-auth-watch`): started from `entrypoint`; `inotifywait` on `$HOME/.sfdx` org auth `*@*.json` (skips alias/key/config). If ≥20 close_write/moved_to/create events on one file in 30s (workaround for salesforcedx-vscode#8470 after sleep), kill Code/Cursor extension hosts via cmdline patterns (`--inspect-port=0`, `extensionHost`) — never cache PIDs; 60s cooldown; Electron respawns hosts. No notifications, no Salesforce API calls. Tunables: `SFDX_AUTH_STORM_THRESHOLD`, `SFDX_AUTH_STORM_WINDOW_SECS`, `SFDX_AUTH_STORM_COOLDOWN_SECS`, `SFDX_AUTH_DIR`.

## Font/GTK Strategy (Current)
- Keep host font/fontconfig mounts in `scripts/host/host-mounts`, including:
  - `/etc/fonts`
  - `/usr/share/fonts`
  - `/usr/local/share/fonts`
  - `~/.local/share/fonts`
  - `~/.fonts`
  - `~/.config/fontconfig`
- Do **not** mount host GTK `settings.ini` directly.
- Generate GTK settings dynamically via `scripts/host/host-gtk-settings`:
  - Prefer host GNOME `gsettings` (DBus) values.
  - Fallback: copy host/system GTK config files as-is.
  - Mount generated files to `/etc/gtk-3.0/settings.ini` and `/etc/gtk-4.0/settings.ini`.

## High-Value Files
- `start` (command dispatcher)
- `scripts/host/install` / `uninstall`
- `scripts/host/run` / `service-start` / `service-status` / `exec-in`
- `scripts/host/host-mounts` / `host-podman-exec` / `host-gtk-settings`
- `scripts/host/app-runners/*` / `scripts/host/wrappers/*`
- `scripts/container/entrypoint` / `vpn-updown` / `sfdx-auth-watch`
- `scripts/dev/build` / `clear-build-cache` / `configure-vpn`
- `config/vpn/` / `config/proxy/` / `config/shell/`
