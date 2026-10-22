# Agent Instructions

Read this file before changing the project. Priority: current user instruction > this file > defaults. If they conflict, follow the user and update this file when the decision should persist.

## Consistency

- **No backward compatibility** unless the user asks in this session (no migration shims, dual paths, or old-name cleanup).
- Keep project `src/host/{run,service-start,service-status}` aligned with installed `/usr/local/lib/work_container/src`.
- Layout: `src/host/` (install/runtime, `app-runners/`, `wrappers/`, `desktop/`, `host-open/`), `src/container/` (image entrypoint; `COPY`’d), `src/dev/` (build/configure; project-only).
- Config pattern: templates under `config/{vpn,proxy,shell,agent,xdg}/` → runtime under `/etc/...` in the container (same as VPN). Passwd/group: mount a merge of `/etc` + `/usr/lib` when altfiles exist (Atomic stubs); otherwise `/etc` as-is — keeps `nobody`/`nogroup` for tinyproxy.
- Status = real runtime (socket/process/log), not configured-only. Logs: plain text, no custom bracket prefixes.
- Say **image** (not archive). No new runtime deps unless requested.
- Consistency changes: update code and this file in the same task.

## Shape

- `./start` → `src/host/` or `src/dev/`. Container/service name: `work_container`.
- Install flattens host runtime into `/usr/local/lib/work_container/src` (+ `config/`); wrappers → `/usr/local/bin`.
- `resolve-paths`: project = `src/host/../../`; installed = `…/work_container` (sibling `config/`).
- Container APP_HOME: `~/.containers/work_container/home` (`HOME`/`XDG_*`/`BROWSER`/`WORK_CONTAINER_HOST_HOME` set in `service-start`). Host home bind-mounted at the same absolute paths; service cwd = host home.
- `exec-in` / `work-container-app` / `sf`: `--workdir "${PWD}"` (must exist in container). `work-shell`: same, else fall back to container `HOME`.
- `config/agent/`: in-container `AGENTS.md` + Cursor rule; install seeds APP_HOME `~/AGENTS.md` and `~/.cursor/rules/work-container.mdc`.

## VPN / network / proxy

- Kill-switch (`entrypoint`): IPv4 default DROP; internet only via IPsec policy; IKE UDP to `VPN_SERVER_IP`; TCP to bridge GW for host-only backends; tinyproxy INPUT on `NODE_PROXY_PORT`; IPv6 all DROP; `TCPMSS --clamp-mss-to-pmtu` on IPsec OUTPUT. Tests: `tests/verify-killswitch-features.sh`.
- IPv4-only (`gai.conf`, `disable_ipv6`). Bridge MTU 1400; charon MSS 1360; child `copy_df`. DNS from gateway via `vpn-updown` (`PLUTO_DNS4_*`) — no hardcoded resolvers.
- Watchdog: retry while down; do not exit the container if VPN is initially down. DPD: `dpd_delay=10s`, child `dpd_action=restart`. “Public egress IP” log = connectivity check only.
- Proxy: `config/proxy/`; render to `/etc/tinyproxy/tinyproxy.conf`. `service-start`/`service-status` report listen-socket reality.

## GUI / host bridges

- Desktop: `src/host/desktop/apps/` → `~/.local/share/applications`; Tela SVGs in `desktop/icons/` → `~/.local/share/icons/hicolor/scalable/apps`. Launch via `work-container-app` (no per-app host wrappers).
- App-runners (host-owned, bind-mounted into container): must `exec` the real Electron/Chrome binary, not the mount path (`chrome` → `/opt/google/chrome/chrome`, `code` → `/usr/share/code/code`, `cursor` → `/usr/share/cursor/cursor`, github-desktop → `/usr/lib/...`). `BROWSER=/usr/local/bin/chrome-work-open`.
- GUI session: Wayland + `DBUS_SESSION_BUS_ADDRESS` via `podman_append_gui_session_env`. Timezone: `TZ` + zoneinfo file mount (not symlink `/etc/localtime` alone).
- `service-start`: systemd has no session env — infer `WAYLAND_DISPLAY` from `wayland-0`, and `DISPLAY`/`XAUTHORITY` from `/tmp/.X11-unix` + mutter auth when present (same “pass what exists” rule).
- `WAIT_FOR_GUI=1` (systemd install): wait for Wayland only; GPU render node and Pulse are optional — start anyway (headless/VPN OK; apps use software GL if no `/dev/dri/renderD*`).
- Devices: `--privileged`, `/dev:/dev:rslave`, `/run/udev:ro` when present, optional `pcscd` rundir.
- Host-open (`src/host/host-open/`): `bin/*`, optional `apps/*.desktop`, `bind-paths.list`, `config/xdg/mimeapps.list` — mounted generically by `host-mounts`. No http(s) mapping (VPN Chrome). `host-shell` = SSH to `host.containers.internal` (passwd home keys, not APP_HOME).
- Fonts: mount host fontconfig/font dirs. Do **not** mount host GTK `settings.ini`; generate via `host-gtk-settings` (gsettings, else copy) → `/etc/gtk-3.0|4.0/settings.ini`.

## Image / tools

- Build layers cache forever without `--no-cache`; stale Chrome/Code/Cursor/`sf`/etc. until `./start clear-build-cache` then rebuild. Cursor CLI (`agent`) in image under `/opt/cursor-agent`, on PATH; no host wrapper — use `work-shell`. Prefer rebuild over `agent update` to image `/opt`.
- `mise`/`pipx` + agent CLIs (`rg`, `fd`, `jq`, …) in image; user runtimes persist in APP_HOME. No compilers / extra tool repos in image by default.
- SF auth storm watch (`sfdx-auth-watch`): if ≥20 writes to one `~/.sfdx` org auth JSON in 30s, kill Code/Cursor extension hosts; 60s cooldown. Tunables `SFDX_AUTH_STORM_*`.

## Touch often

`start`, `src/host/{install,uninstall,ensure-host-deps,service-*,run,exec-in,host-mounts,host-podman-exec,host-gtk-settings,app-runners,wrappers,host-open,desktop}`, `src/container/{entrypoint,vpn-updown,sfdx-auth-watch}`, `src/dev/{build,clear-build-cache,configure-vpn}`, `config/{vpn,proxy,shell,agent,xdg}/`.
