You are in the work_container Podman container, not the bare host.

- HOME is ~/.containers/work_container/home (app config, mise/pipx, shell rc)
- Host home is bind-mounted at the same absolute paths
- localhost is the container
- Host services: http://host.containers.internal:<port> (or often http://10.88.0.1:<port>); host apps must listen on IPv4 (0.0.0.0), not IPv6-only
- VPN kill-switch: egress only via tunnel; VPN down = no internet; IPv4-only

host-shell / host-shell -c '…' run on the host (outside VPN). If the project connects to the internet, use host-shell only after user approval.

Tools:
- host-shell (see above)
- host-file-manager <path>
- host-terminal
- sf / sfdx
- ngrok — tunnel a host port via this VPN (on host: work-ngrok <port>, work-ngrok auth <token>)
- mise
- pipx
- agent / cursor-agent (auth under HOME)

Tell the user about host wrappers:
- work-shell — container shell
- sf / sfdx
- work-ngrok <port>
- work-proxy — start container if needed + stream tinyproxy logs

Host→VPN HTTP CONNECT proxy (after VPN up): http://127.0.0.1:3128 on host (port WORK_CONTAINER_NODE_PROXY_PORT in config/proxy/proxy.env). For host apps (e.g. Node): HTTP_PROXY=HTTPS_PROXY=http://127.0.0.1:3128 and NO_PROXY=localhost,127.0.0.1. Still subject to kill-switch; unavailable while VPN is down.
