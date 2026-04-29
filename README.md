# work_container

Single Podman container with:
- StrongSwan VPN client (inside the container)
- Salesforce CLI (`sf`)
- Google Chrome
- Firefox ESR

The host does **not** need to be connected to VPN.  
The container uses a kill-switch policy: if VPN is not up, container egress stays blocked.
Scripts use `sudo podman` (rootful mode), required for reliable IPsec behavior.

## 1) Ubuntu 25.10 packages to install on host

```bash
sudo apt update
sudo apt install -y podman uidmap slirp4netns fuse-overlayfs xauth
```

For X11 GUI access from container apps:

```bash
xhost +si:localuser:$USER
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
- install a sudoers rule for passwordless `podman` (required for desktop launchers and `./start app ...`)
- install/update system service `work_container.service` (on-demand start via app runner)

After first install, `sf`/`sfdx` are available as system binaries.

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

## 6) Update packages after image is already built

### Recommended: rebuild image

Rebuilding is cleaner and reproducible:

```bash
./start build
```

### Helper script

Use the included helper:

```bash
./start update
```

This always:
- loads the newest build archive from `containers/`
- updates APT packages and refreshes Salesforce CLI (`sf`) in that image
- creates a new build version archive in `containers/`

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
- `service-start` runs with `apparmor=unconfined` to allow DBus access from container apps.
- VPN credentials are stored in `config/vpn.env` on host, not baked into image.
- If VPN negotiation fails, entrypoint exits and internet remains blocked for the container process.
- Use `./start` as the single entry point; it can run build/run/update/service/exec-in commands.
- `./start` with no args opens an interactive selection menu.

## 8) Desktop launchers on host

Install user-level desktop entries:

```bash
./start install-desktop
```

This installs launchers into:

`~/.local/share/applications`

Created entries:
- `Google Chrome (Work)`
- `Firefox (Work)`

They run apps from the running service container through `./start`, so traffic still goes via container VPN.
