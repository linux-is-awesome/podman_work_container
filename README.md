<p align="center">
  <img src="https://raw.githubusercontent.com/containers/podman/main/logo/podman-logo.png" alt="Podman" width="120" />
</p>

<h1 align="center">Work Container</h1>

<p align="center">
  <strong>Isolated Linux workstation in one Podman container</strong><br />
  VPN kill-switch · GUI apps · Salesforce CLI · host bridges
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black" alt="Linux" />
  <img src="https://img.shields.io/badge/Podman-892CA0?style=flat-square&logo=podman&logoColor=white" alt="Podman" />
  <img src="https://img.shields.io/badge/VPN-strongSwan-0A66C2?style=flat-square" alt="strongSwan" />
  <img src="https://img.shields.io/badge/GUI-Wayland-2ECC71?style=flat-square" alt="Wayland" />
  <img src="https://img.shields.io/badge/mode-rootful-critical?style=flat-square" alt="rootful" />
</p>

<p align="center">
  <a href="#whats-inside">What's inside</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#host-wrappers">Host wrappers</a> ·
  <a href="#service">Service</a>
</p>

---

## Why

Corporate VPN is often required for browsers, IDEs, and CLIs — but putting the **whole host** on that VPN is noisy, sticky, and easy to get wrong.

This project keeps the host off the VPN and runs the work toolchain in one Podman container instead. A kill-switch blocks container egress when the tunnel is down, so traffic does not silently fall back to your ISP. The container is on demand: bring it up for a work session, stop it when you are done.

Project files stay on the host at normal paths; app settings stay in an isolated APP_HOME so host Chrome/Code profiles are not mixed with the VPN ones.

Linux only (Debian/Ubuntu, Fedora/RHEL-family, Arch, Atomic/Silverblue). Rootful Podman is required for reliable IPsec.

## What's inside

- **Network** — strongSwan IKEv2, IPv4-only kill-switch (IPv6 dropped), tinyproxy on host `127.0.0.1:3128`
- **Browsers** — Google Chrome, Firefox ESR (host Wayland / GPU / Pulse)
- **Editors** — VS Code, Cursor (+ `agent` CLI via `work-shell`)
- **Salesforce** — `sf` / `sfdx` host wrappers → container CLI
- **Tooling** — mise, pipx, common agent CLIs (`rg`, `fd`, `jq`, …)
- **Desktop** — `.desktop` launchers + hicolor icons under `/usr/local`
- **Host bridges** — `host-shell`, `host-terminal`, `work-ngrok`, `work-proxy`, `mise-export` (plus host DBus / SSH agent forwarding)

Images build to `work_container:latest` and `containers/work_container-*.oci`.

Persistent home for container apps: `~/.containers/work_container/home`.  
Your real host home is also bind-mounted so project paths match inside and out.

## Quick start

```bash
git clone https://github.com/linux-is-awesome/podman_work_container.git
cd podman_work_container
./setup
```

`./setup` opens an interactive menu (host deps are checked first). Typical first-time path:

1. **Configure VPN** — writes `config/vpn/vpn.env` (server, credentials). Needed before the container can reach the internet.
2. **Build image** — cached build for day-to-day changes, or **build fresh** to re-fetch Chrome/Code/Cursor/`sf` with no cache.
3. **Install/update system integration** — systemd unit, desktop launchers, PATH wrappers (`work-shell`, `sf`, …), sudoers for rootful Podman. Does not leave the container running.
4. **Apps** (or desktop launchers / `work-shell`) — start the on-demand service and open Chrome, Firefox, VS Code, Cursor, GitHub Desktop, or `sf`.

Service start/stop/status are also in the menu when you want the tunnel without opening an app. Nothing starts at boot.

## Configuration

VPN, proxy, install/uninstall, and service lifecycle are all available from the `./setup` menu. Credentials live in host-side `config/vpn/vpn.env` (never baked into the image). Edit templates under `config/` and restart the service to apply.

### Host → container HTTP proxy

Default: `http://127.0.0.1:3128` (localhost only). Optional `config/proxy.env`:

```bash
WORK_CONTAINER_NODE_PROXY_PORT=3128
```

Point host apps at it with `HTTP_PROXY` / `HTTPS_PROXY`. Traffic still follows the kill-switch.

### Reach host dev servers from container Chrome

The kill-switch still allows TCP to the Podman bridge for **host-only** backends (`host.containers.internal`) — not general internet. Bind your host app to IPv4 (`0.0.0.0`), then open:

`http://host.containers.internal:<port>`

### Host shell from inside the container

Some work needs the **host** (native binaries, host `~`) while you stay on the same project path. From a container terminal (`work-shell` or an IDE terminal inside the container):

```bash
host-shell            # interactive host shell at the current directory
host-shell -c 'pwd'   # one-shot command on the host
```

### Export mise tools to the host (`mise-export`)

**Why:** mise (Node, etc.) lives in the **container** APP_HOME. A normal host terminal does not see those tools. If you use `host-shell` as your IDE terminal, or run commands on the host at the project path, you still want `node` / `npm` / `mise` without installing the same stack twice on the host.

**What it does:** run `mise-export` **inside the container** after `mise install` / `mise use`. It registers a shim under APP_HOME. Install adds a hook in the host `~/.bashrc` so both native host terminals and `host-shell` put those shims on `PATH`. Invoking a shim runs the tool **inside** `work_container` at your current directory (starts the service if needed). The host never needs its own Node install for those commands.

```bash
# inside work-shell / container IDE terminal
mise use --global node@lts
mise-export mise
mise-export node
mise-export npm

mise-export --list
mise-export --remove npm
```

Open a new `host-shell` (or `hash -r` in an existing one) after exporting. Then on the host side:

```bash
host-shell -c 'node --version'
host-shell -c 'npm --version'
```

<details>
<summary><strong>VS Code / Cursor: default terminal on host (per project)</strong></summary>

In that project’s `.vscode/settings.json`:

```json
{
  "terminal.integrated.profiles.linux": {
    "Host": { "path": "host-shell" }
  },
  "terminal.integrated.defaultProfile.linux": "Host",
  "terminal.integrated.automationProfile.linux": {
    "path": "host-shell"
  }
}
```

</details>

<details>
<summary><strong>GitHub Desktop → Custom Editor router</strong></summary>

Set **Custom Editor** to `/usr/local/bin/work-editor-open` with argument `%TARGET_PATH%`.

Routes (longest prefix wins) live in container APP_HOME  
`~/.config/work-editor-routing.conf` (seeded from `config/routing/`).

</details>

<details>
<summary><strong>SSH / git</strong></summary>

Keys live under APP_HOME `~/.ssh`. The host `SSH_AUTH_SOCK` is forwarded so unlocked keys cache in the host agent for the desktop session. A seeded `~/.ssh/config` sets `AddKeysToAgent yes` when that file is missing.
</details>

## Host wrappers

`./setup` install puts these on the host `PATH` (`/usr/local/bin`). If the container is stopped, they start `work_container.service` first, then run inside it.

**`work-shell`** — interactive shell in the container at your current directory (falls back to container home). Pass a command to run non-interactively:

```bash
work-shell
work-shell sf org list
work-shell agent --help
```

**`sf` / `sfdx`** — same Salesforce CLI as inside the container, from any host directory that exists in the container:

```bash
sf --version
sf org list
```

**`work-ngrok`** — expose a **host** port through the container VPN path:

```bash
work-ngrok auth <YOUR_TOKEN>
work-ngrok 4173
```

**`work-proxy`** — stream tinyproxy connection logs (starts the service if needed):

```bash
work-proxy
```

**`work-container-app`** — used by desktop launchers (Chrome Work, Cursor Work, …). Prefer the app menu or `work-shell` for day-to-day use.

Inside the container (IDE terminal / `work-shell`), host bridges are separate: `host-shell`, `host-terminal`, `mise-export`, `work-editor-open`.

## Service

The container is **not** an always-on daemon. Install only registers systemd unit `work_container.service` — it is **not** enabled at boot and does not run until something starts it.

It starts when you:

- open a desktop app (Chrome Work, Cursor Work, …),
- run a host wrapper (`work-shell`, `sf`, …), or
- start it yourself from `./setup` / `systemctl`.

When you are done, stop it to free resources and drop the VPN tunnel:

```bash
./setup service-stop
# or
sudo systemctl stop work_container.service
```

Check whether it is running (egress IP, proxy, recent logs):

```bash
./setup service-status
# or
sudo systemctl status work_container.service
```

Start or restart manually when you want the tunnel/apps without launching a wrapper first:

```bash
./setup service-start
./setup service-stop && ./setup service-start
# or
sudo systemctl restart work_container.service
```

Restart after VPN config changes so the container reloads `config/vpn/`.
