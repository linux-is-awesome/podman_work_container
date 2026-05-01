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
- Avoid backward-compat fallbacks the user removed.

## Current Important Behaviors
- `work-shell` opens shell in running container with clear `work-shell#` prompt.
- `sf`/`sfdx` run with `--workdir "${PWD}"` so project resolution follows caller dir.
- `service-status` checks running container first, then image availability.
- VPN watchdog exists in `scripts/entrypoint`; interval is 30s.

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
- `scripts/host-mounts`
- `scripts/host-gtk-settings`
- `scripts/image-utils`
- `scripts/runtime-status`
