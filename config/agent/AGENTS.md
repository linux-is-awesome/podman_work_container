You are in the work_container Podman container, not the bare host.

- HOME is ~/.containers/work_container/home (app config, mise/pipx, shell rc)
- Host home is bind-mounted at the same absolute paths
- localhost is the container
- Host services: http://host.containers.internal:<port> (or often http://10.88.0.1:<port>); host apps must listen on IPv4 (0.0.0.0), not IPv6-only
- VPN kill-switch: egress only via tunnel; VPN down = no internet; IPv4-only

Restricted tools (run on the host):
Rules:
1. Do not use these tools unless needed for the user's request.
2. NEVER send internet / outbound network traffic through them unless the user has given a separate, explicit approval in this conversation for that specific call (or a clearly scoped set of calls).
3. Asking whether something is possible is not approval. Answer only; for a host-network call, ask first and wait for a clear yes.
4. Approval is one-shot for the stated action unless the user says otherwise. Do not reuse it for later callouts.
- host-shell / host-shell -c '…' (wait + logs/exit like host bash; KillMode=process keeps gtk-launch / steps/launch children)
- host-terminal
Before using these tools (especially with network), re-read Rules above.

Tools:
- host-file-manager <path>
- sf / sfdx
- ngrok — tunnel a host port via this VPN (on host: work-ngrok <port>, work-ngrok auth <token>)
- mise — prefer this for toolchains like Node.js, etc.
- pipx

Tell the user about host wrappers:
- work-shell — container shell
- sf / sfdx
- work-ngrok <port>
- work-proxy — start container if needed + stream tinyproxy logs

Host→VPN HTTP CONNECT proxy (after VPN up): http://127.0.0.1:3128 on host (port WORK_CONTAINER_NODE_PROXY_PORT in config/proxy/proxy.env). For host apps (e.g. Node): HTTP_PROXY=HTTPS_PROXY=http://127.0.0.1:3128 and NO_PROXY=localhost,127.0.0.1. Still subject to kill-switch; unavailable while VPN is down.
