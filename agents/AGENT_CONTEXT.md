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
- `work-shell` opens shell in running container with clear `work-shell#` prompt.
- `sf`/`sfdx` run with `--workdir "${PWD}"` so project resolution follows caller dir.
- `service-status` checks running container first, then image availability.
- VPN watchdog in `scripts/entrypoint`: retries every 5s while unhealthy, every 30s when tunnel+DNS OK; checks CHILD_SA and DNS (`getent`), not IKE name alone; logs `VPN watchdog: network OK (tunnel and DNS working again)` plus public egress IP when recovering after a drop (not duplicated if already healthy at startup).
- VPN DNS: `scripts/vpn-updown` writes `/etc/resolv.conf` from `PLUTO_DNS4_*` on CHILD up (`config/swanctl.conf.template` `updown = …`); no hardcoded resolver IPs.
- VPN path is **IPv4-only**: entrypoint disables container IPv6 (`config/gai.conf` prefers IPv4 in glibc). Bridge iface MTU set to 1400 in entrypoint/vpn-updown (`WORK_CONTAINER_IFACE_MTU`). strongSwan `kernel-netlink.mss = 1360` plus iptables `TCPMSS --clamp-mss-to-pmtu` on IPsec OUTPUT; swanctl child uses `copy_df`. No per-app network flags.
- VPN startup must not terminate the container if tunnel/DNS is down initially; watchdog keeps retrying while container/apps remain usable.
- `Public egress IP` log line is a post-connectivity curl check only, not kill-switch config.
- Logs should use plain text without `[work_container]`/`[start ...]` prefixes.
- Proxy support is Node-focused via tinyproxy on host-local port (default `3128`), configurable through `config/proxy.env`.
- Proxy template is `config/tinyproxy.conf.template`; runtime proxy config is rendered under `/etc/tinyproxy/tinyproxy.conf` (not `/tmp`).
- `service-start` and `service-status` should report real proxy status (based on host listening socket), not just configured endpoint text.
- VPN kill-switch in `scripts/entrypoint`: IPv4 default DROP; egress internet only via `-m policy --pol ipsec`; IKE UDP to `VPN_SERVER_IP`; TCP to bridge gateway for host dev/Chrome/ngrok backend only; INPUT TCP dport `NODE_PROXY_PORT` for published tinyproxy; `ip6tables` all DROP; mangle `TCPMSS --clamp-mss-to-pmtu` on IPsec OUTPUT only. Manual checks: `tests/verify-killswitch-features.sh` (see `tests/README.md`).
- Host → container exec: `scripts/host-podman-exec` `podman_exec_stdio_args` (`-i` always; `-t` only when stdin and stdout are TTYs). Used by `exec-in`, `work-container-app`, `work-shell`, `work-ngrok`. Do not `exec` into `podman exec`/`podman logs` from wrappers—keep a host shell for signal/session teardown. Probe/helper `podman exec` calls that only read output use `-i` alone.

- Devices: `scripts/host-mounts` `add_host_usb_devices` — `--privileged` and `/dev:/dev:rslave` (host hot-plug, same ACLs); optional `pcscd` socket. Wired from `service-start` and `run`. VPN kill-switch unchanged.

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
- `scripts/host-gtk-settings`
- `scripts/image-utils`
- `scripts/runtime-status`
