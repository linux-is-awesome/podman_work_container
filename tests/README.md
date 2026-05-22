# Manual integration checks

Requires `work_container` running and rootful podman (`sudo podman`).

```bash
sudo ./tests/verify-killswitch-features.sh   # kill-switch, proxy, ngrok path
sudo ./tests/test-vpn-egress.sh            # DNS, HTTPS, TLS inside container
sudo ./tests/compare-vpn-network.sh        # host vs container network snapshot
```
