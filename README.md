# Podman Work Container

Single Podman container (`work_container` image and service) with:
- StrongSwan VPN client (inside the container)
- Salesforce CLI (`sf`)
- Google Chrome
- Firefox ESR

The host does **not** need to be connected to VPN.  
The container uses a kill-switch policy: if VPN is not up, container egress stays blocked.
Scripts use `sudo podman` (rootful mode), required for reliable IPsec behavior.

## 1) Packages to install on host (Debian-based)

```bash
sudo apt update
sudo apt install -y podman uidmap slirp4netns fuse-overlayfs xauth
```

## 2) Install/Update on host

Run:

```bash
./start install
```

This command will:
- build image if no build archive exists yet
- copy latest build archive to `~/.containers` (old versions there are removed)
- install/update desktop entries in `~/.local/share/applications`
- install `sf`/`sfdx` wrapper binaries in `/usr/local/bin` to use container CLI
- install `work-shell` at `/usr/local/bin/work-shell` (run on the host for an interactive shell in the running container)
- install `work-ngrok` at `/usr/local/bin/work-ngrok` (run ngrok inside container for a host port)
- install `work-proxy` at `/usr/local/bin/work-proxy` (tail proxy connection logs from container)
- install a sudoers rule for passwordless `podman` (required for desktop launchers and `./start app ...`)
- install/update system service `work_container.service` (on-demand start via app runner)

After first install, `sf`/`sfdx` are available as system binaries. Run `work-shell` from the host for an interactive shell in the container; if it is not running, the wrapper restarts `work_container.service` first.

To remove integration:

```bash
./start uninstall
```

## 3) Configure VPN outside the container

Host certs are synced automatically during:
- `./start build`
- `./start run`
- `./start service-start`

Manual sync is still available:

```bash
./start sync-certs
```

Run:

```bash
./start configure-vpn
```

This creates `config/vpn.env`.

If needed, edit `config/vpn.env` manually later (username/password/server/options).  
Optionally edit `config/swanctl.conf.template` for advanced changes.  
This file is mounted from host, so no rebuild is required.

Proxy settings are separate in `config/proxy.env` (optional).  
Create it from template when needed:

```bash
cp config/proxy.env.template config/proxy.env
```

Proxy server template is in `config/tinyproxy.conf.template` (mounted from host).

Certificate sources used by the container:
- project snapshot: `certs/host` (from `./start sync-certs`)
- project custom certs: `certs/custom`
- live host cert store mounted in container

## 4) Build image

```bash
./start build
```

This always builds image `work_container:latest` and saves it to:

`containers/work_container-YYYYMMDD-HHMMSS.oci`

Example:

`containers/work_container-20260429-132501.oci`

## 5) Run container

```bash
./start run
```

This loads and runs the newest build version found in `containers/`.

Run specific build version:

```bash
./start run 20260429-132501
```

Run a specific app directly:

```bash
./start app google-chrome
./start app firefox
./start app sf --version
```

## 4b) Run as persistent service (recommended for host tools)

Start service (latest build):

```bash
./start service-start
```

Alias command (same behavior):

```bash
./start start-service
```

If GUI apps fail after login/session changes, restart service so new display/runtime mounts apply:

```bash
./start service-stop
./start service-start
```

Start specific build:

```bash
./start service-start 20260429-132501
```

Check status/log tail:

```bash
./start service-status
```

Stop service:

```bash
./start service-stop
```

Run tools from the running service container:

```bash
./start app sf --version
./start app google-chrome
./start app firefox
```

Access host-local apps from inside container apps (for example Chrome):

- `localhost` inside container is not host `localhost`
- use host bridge gateway address: `http://10.88.0.1:<port>`
- equivalent host alias is usually available: `http://host.containers.internal:<port>`
- bind your host app to IPv4 (for example `0.0.0.0`), not only IPv6

Example:

```bash
vite --host 0.0.0.0 --port 4173
```

Then open from container Chrome:

`http://10.88.0.1:4173`

or:

`http://host.containers.internal:4173`

Run ngrok from inside container (manual, not auto-start):

```bash
work-ngrok 4173
```

This exposes host app port `4173` via container/VPN path.

Set ngrok auth token for the wrapper path:

```bash
work-ngrok auth <YOUR_TOKEN>
```

`work-ngrok` uses isolated config/cache/data paths under:

`~/.containers/work_container/home`

Tail proxy connection logs (starts service if needed):

```bash
work-proxy
```

Service mode mounts your full host home directory as read/write at the same path,
so container tools/apps can work with your normal files.

`exec-in` stores app/tool configs in:

`~/.containers/work_container/home`

This keeps container app settings isolated from your normal host app configs.

## 5) Update VPN settings without rebuild

Edit `config/vpn.env` and/or `config/swanctl.conf.template`, then restart container:

```bash
./start run
```

No image rebuild needed for VPN config changes.

## 5b) Route Node.js API calls via container VPN

The container starts a local HTTP CONNECT proxy after VPN is up.

Default host endpoint:

`http://127.0.0.1:3128`

Configure proxy port for the container in `config/proxy.env`:

```bash
WORK_CONTAINER_NODE_PROXY_PORT=3128
```

Then restart the container service:

```bash
./start service-stop
./start service-start
```

Set proxy values in your Node app `.env` file:

```bash
HTTP_PROXY=http://127.0.0.1:3128
HTTPS_PROXY=http://127.0.0.1:3128
NO_PROXY=localhost,127.0.0.1
```

Then start your Node app normally from host.

Notes:
- proxy traffic is still subject to container VPN kill-switch rules
- proxy listens on localhost only (`127.0.0.1`) on host
- if VPN is not up, container exits and proxy is unavailable
- if `config/proxy.env` is absent, default port `3128` is used

How to check your Node app is using the proxy:
- confirm proxy listener is up on host:
  - `ss -ltnp | rg ':3128'`
- inspect proxy connection logs on host:
  - `sudo podman logs -f work_container 2>&1 | grep -Ei 'tinyproxy|connect|request|opensock|upstream|client|closed connection'`
- run app with debug output from Node HTTP stack:
  - `NODE_DEBUG=http,https <your start command>`
  - look for connection attempts to `127.0.0.1:3128`
- verify requests use VPN egress IP:
  - from your app, call `https://ifconfig.me/ip`
  - compare with `sudo podman logs work_container | rg "Public egress IP"`
  - quick host one-liner through proxy: `curl -fsS --max-time 15 --proxy "http://127.0.0.1:3128" https://ifconfig.me/ip`

## 6) Update packages after image is already built

Rebuild the image so changes stay reproducible:

```bash
./start build
```

## 7) Portable single-file image

Save:

```bash
podman save --format oci-archive -o work_container.oci work_container:latest
```

Load on a fresh OS:

```bash
podman load -i work_container.oci
```

Your scripts already keep portable archives at:

`containers/work_container-*.oci`

## Notes

- The current setup is designed for Linux hosts.
- Scripts run with rootful Podman (`sudo`) and `run` uses an isolated bridge network.
- `service-start` mounts `${HOME}` read/write into the container at the same path.
- `service-start` also mounts host display/runtime resources, `/dev/dri`, `/dev/snd`, and DBus socket for GUI/GPU/audio integration.
- `service-start` and `run` mount host timezone files (`/etc/localtime`, `/etc/timezone`) and pass `TZ` so container local time matches host.
- `service-start` runs with `apparmor=unconfined` to allow DBus access from container apps.
- VPN credentials are stored in `config/vpn.env` on host, not baked into image.
- If VPN negotiation fails, entrypoint exits and internet remains blocked for the container process.
- Use `./start` as the single entry point; it can run build/run/service/exec-in commands.
- `./start` with no args opens an interactive selection menu.
