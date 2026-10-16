# Work Container Context (Compact)

## Use This First
- Read this file before changes.
- Priority: current user instruction > this file > defaults.

## Project Shape
- Script-driven container workflow in `scripts/*`.
- Installed runtime lives under `/usr/local/lib/work_container`.
- Main service/container name: `work_container`.

## Non-Negotiables
- Keep **project scripts** and **installed runtime behavior** aligned.
- No new runtime dependencies unless explicitly requested.
- Use **image** terminology only (never reintroduce archive naming).
- **No backward compatibility.** Never add migration shims, dual code paths, renamed-file cleanup in install/uninstall, “support old config/layout” branches, or deprecated-option handling unless the user explicitly requests it in the current session.

## Current Important Behaviors
- Container `HOME` / `XDG_*` / `BROWSER` / `WORK_CONTAINER_HOST_HOME` are set once in `service-start` (`work_container_run_app_home_env`); all `podman exec` paths inherit them. App config lives under `~/.containers/work_container/home`. Host home is bind-mounted at the same path for projects/fonts; service/work-shell start cwd is host home.
- `sf`/`sfdx` run with `--workdir "${PWD}"` so project resolution follows caller dir.
- `service-status` checks running container first, then image availability.
- VPN watchdog in `scripts/entrypoint`: retries every 2s while unhealthy, every 10s when tunnel+DNS OK; checks CHILD_SA and DNS (`getent`), not IKE name alone; logs `VPN watchdog: network OK (tunnel and DNS working again)` plus public egress IP when recovering after a drop (not duplicated if already healthy at startup).
- IKEv2 DPD: `dpd_delay = 10s` set on the connection in `config/swanctl.conf.template` (charon default is disabled/0s); `dpd_timeout` has no effect on IKEv2 so it is not set. Child `dpd_action = restart` re-initiates the CHILD_SA under a fresh IKE_SA when DPD detects the peer is unresponsive.
- `podman build` (via `scripts/build`) has no `--no-cache`/cache-busting `ARG`, so unchanged Containerfile layers (base apt incl. agent/file tools, Chrome/VS Code/Cursor/`sf`/ngrok/mise curl+apt installs) are reused across rebuilds indefinitely — verified a rebuild reused an 8-week-old cached image byte-for-byte (same Image ID), serving stale app versions. `./start clear-build-cache` (`scripts/clear-build-cache`, `sudo podman image prune -f`) clears the dangling/cache layers so the next `./start build` fetches fresh versions; normal `./start build` stays cached/fast for iterative testing. Not wired into the installed runtime bundle (build-only scripts like `build`/`run`/`configure-vpn` stay project-local, not copied to `/usr/local/lib/work_container`).
- Cursor: installed in `Containerfile` from the official Anysphere apt repo (`downloads.cursor.com/aptrepo` + `downloads.cursor.com/keys/anysphere.asc`), same pattern as the VS Code repo (unpinned `apt-get install -y cursor`, so a genuinely fresh `./start build` gets latest). GUI launcher: `scripts/cursor-work-open` bind-mounted on `/usr/bin/cursor` (real Anysphere `/usr/bin/cursor` symlink target is `/usr/share/cursor/bin/cursor`, a CLI/tunnel router script — must `exec /usr/share/cursor/cursor` directly, the Electron binary, not `bin/cursor`); desktop entry `Icon=co.anysphere.cursor`, `StartupWMClass=Cursor` (verified against the real `.deb`'s shipped `cursor.desktop`).
- VPN DNS: `scripts/vpn-updown` writes `/etc/resolv.conf` from `PLUTO_DNS4_*` on CHILD up (`config/swanctl.conf.template` `updown = …`); no hardcoded resolver IPs.
- VPN path is **IPv4-only**: entrypoint disables container IPv6 (`config/gai.conf` prefers IPv4 in glibc). Bridge iface MTU set to 1400 in entrypoint/vpn-updown (`WORK_CONTAINER_IFACE_MTU`). strongSwan `kernel-netlink.mss = 1360` plus iptables `TCPMSS --clamp-mss-to-pmtu` on IPsec OUTPUT; swanctl child uses `copy_df`. No per-app network flags.
- VPN startup must not terminate the container if tunnel/DNS is down initially; watchdog keeps retrying while container/apps remain usable.
- `Public egress IP` log line is a post-connectivity curl check only, not kill-switch config.
- Logs should use plain text without `[work_container]`/`[start ...]` prefixes.
- Proxy support is Node-focused via tinyproxy on host-local port (default `3128`), configurable through `config/proxy.env`.
- Proxy template is `config/tinyproxy.conf.template`; runtime proxy config is rendered under `/etc/tinyproxy/tinyproxy.conf` (not `/tmp`).
- `service-start` and `service-status` should report real proxy status (based on host listening socket), not just configured endpoint text.
- VPN kill-switch in `scripts/entrypoint`: IPv4 default DROP; egress internet only via `-m policy --pol ipsec`; IKE UDP to `VPN_SERVER_IP`; TCP to bridge gateway for host dev/Chrome/ngrok backend only; INPUT TCP dport `NODE_PROXY_PORT` for published tinyproxy; `ip6tables` all DROP; mangle `TCPMSS --clamp-mss-to-pmtu` on IPsec OUTPUT only. Manual checks: `tests/verify-killswitch-features.sh` (see `tests/README.md`).
- Host → container exec: `scripts/host-podman-exec` — all app/tool commands use `work_container_exec_as_user` (setpriv to host uid/gid/groups). GUI launches add session env via `podman_append_gui_session_env`. Stdio: `podman_exec_stdio_args` (`-i` always; `-t` when both streams are TTYs); probes set `WORK_CONTAINER_EXEC_STDIO=probe` for `-i` only. `work-proxy` uses `podman logs` only (no exec).

- Devices: `scripts/host-mounts` `add_host_usb_devices` — `--privileged` and `/dev:/dev:rslave` (host hot-plug, same ACLs); `/run/udev:ro` when present (libudev add/remove for Chrome FIDO/HID after USB replug); optional host `pcscd` rundir (`/run/pcscd` or `/var/run/pcscd`) so a socket started later is visible. Wired from `service-start` and `run`. VPN kill-switch unchanged.
- GUI apps (Chrome, Firefox, VS Code, Cursor): host desktop entries call `work-container-app <app>` (no per-app `work-*` wrappers). Desktop files under `desktop/` install to `~/.local/share/applications` with MIME handlers so they appear in host Default Applications: browsers use `Exec=… %U` + `x-scheme-handler/http(s)` / `text/html`; editors use `Exec=… %F` + `text/plain` / `inode/directory` / `application/x-code-workspace` and `TextEditor` category. Install does not force defaults (user picks in Settings or `xdg-settings`/`xdg-mime`). Runner passes URL/file args through; Chrome/Firefox flags come before `"$@"` so `%U` stays valid. Host paths outside the bind-mounted home may not open. Chrome: `scripts/chrome-work-open` bind-mounted on `/usr/bin/google-chrome-stable` and `/usr/local/bin/google-chrome`; must `exec /opt/google/chrome/chrome` (not `google-chrome-stable`, mount target). Set `BROWSER=/usr/local/bin/chrome-work-open` in container GUI env (`exec-in`, `work-container-app`) for xdg-open / VS Code external links. VS Code: `scripts/vscode-work-open` on `/usr/bin/code`; `exec /usr/share/code/code`; `StartupWMClass=code`. Cursor: `scripts/cursor-work-open` on `/usr/bin/cursor`; `exec /usr/share/cursor/cursor`; `StartupWMClass=Cursor`.
- Session D-Bus for portals (color picker / screencast): `service-start`/`run` set `DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus` and `XDG_SESSION_TYPE=wayland`; GUI exec always forwards the same via `podman_append_gui_session_env` so Chrome/VS Code can reach host `xdg-desktop-portal` PickColor.
- Host timezone: `work_container_host_timezone` resolves IANA zone (timedatectl, `/etc/timezone`, `/etc/localtime`); `service-start`/`run` set `TZ` and mount `/usr/share/zoneinfo/<zone>` on `/etc/localtime` (symlink bind-mount is unreliable). GUI exec passes `TZ` via `podman_append_gui_session_env` (Chrome needs `TZ`, not only `/etc/localtime`).
- `mise` is baked into the image at `/usr/local/bin/mise`. User-installed runtimes (`mise install`) persist under `~/.containers/work_container/home` (container `HOME` / `XDG_*`), not in the image layer. Default shell rc ships in `config/bashrc` (includes `mise activate`) and `config/profile`; `service-start` copies them into APP_HOME when `~/.bashrc` / `~/.profile` are missing. `work-shell` runs `bash -i` (normal rc files). Image also includes `pipx` (+ `python3`/`python3-venv`) for CLI apps into APP_HOME.
- Agent/file tooling in the image from Debian repos only (no compilers, no extra tool repos): `rg` (ripgrep), `fd` (symlink to Debian `fdfind`), `jq`, `yq` (Debian/`python3-yq`), `unzip`/`zip`, `file`, `rsync`, `sqlite3`, `tree`, `xxd`, `lsof`. Build toolchains and third-party CLIs (`gh`, etc.) stay out; install per project via `mise`/apt when needed.

## Font/GTK Strategy (Current)
- Keep host font/fontconfig mounts in `scripts/host-mounts`, including:
  - `/etc/fonts`
  - `/usr/share/fonts`
  - `/usr/local/share/fonts`
  - `~/.local/share/fonts`
  - `~/.fonts`
  - `~/.config/fontconfig`
- Do **not** mount host GTK `settings.ini` directly.
- Generate GTK settings dynamically via `scripts/host-gtk-settings`:
  - Prefer host GNOME `gsettings` (DBus) values.
  - Fallback: copy host/system GTK config files as-is.
  - Mount generated files to `/etc/gtk-3.0/settings.ini` and `/etc/gtk-4.0/settings.ini`.

## High-Value Files
- `scripts/install`
- `scripts/run`
- `scripts/service-start`
- `scripts/service-status`
- `scripts/exec-in`
- `scripts/entrypoint`
- `scripts/vpn-updown`
- `scripts/host-mounts` (fonts, USB passthrough)
- `scripts/vscode-work-open` / `scripts/cursor-work-open` (GUI Electron launchers)
- `scripts/host-gtk-settings`
- `scripts/image-utils`
- `scripts/runtime-status`
- `scripts/clear-build-cache`
