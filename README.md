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

## 2) Configure VPN outside the container

Run the interactive script:

```bash
./configure-vpn
```

This creates `config/vpn.env`.

If needed, edit `config/vpn.env` manually later (username/password/server/options).  
Optionally edit `config/swanctl.conf.template` for advanced changes.  
This file is mounted from host, so no rebuild is required.

## 3) Build image

```bash
./build
```

This always builds image `work_container:latest` and saves it to:

`containers/work_container-YYYYMMDD-HHMMSS.oci`

Example:

`containers/work_container-20260429-132501.oci`

## 4) Run container

```bash
./run
```

This loads and runs the newest build version found in `containers/`.

Run specific build version:

```bash
./run 20260429-132501
```

Run a specific app directly:

```bash
./run -- google-chrome-stable
./run -- firefox-esr
```

## 4b) Run as persistent service (recommended for host tools)

Start service (latest build):

```bash
./service-start
```

Start specific build:

```bash
./service-start 20260429-132501
```

Check status/log tail:

```bash
./service-status
```

Stop service:

```bash
./service-stop
```

Run tools from the running service container:

```bash
./exec-in sf --version
./exec-in google-chrome-stable
./exec-in firefox-esr
```

Service mode mounts your full host home directory as read/write at the same path,
so container tools/apps can work with your normal files.

## 5) Update VPN settings without rebuild

Edit `config/vpn.env` and/or `config/swanctl.conf.template`, then restart container:

```bash
./run
```

No image rebuild needed for VPN config changes.

## 6) Update packages after image is already built

### Recommended: rebuild image

Rebuilding is cleaner and reproducible:

```bash
./build
```

### Helper script

Use the included helper:

```bash
./update
```

This always:
- loads the newest build archive from `containers/`
- updates packages in that image
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
- VPN credentials are stored in `config/vpn.env` on host, not baked into image.
- If VPN negotiation fails, entrypoint exits and internet remains blocked for the container process.
- Use only these commands day-to-day: `./configure-vpn`, `./build`, `./run`, `./update`.
- `./run` uses latest build by default and accepts a build version argument.

## 8) Desktop launchers on host

Install user-level desktop entries:

```bash
./install-desktop
```

This installs launchers into:

`~/.local/share/applications`

Created entries:
- `Google Chrome (Work)`
- `Firefox (Work)`

They run apps from the running service container through `./exec-in`, so traffic still goes via container VPN.
