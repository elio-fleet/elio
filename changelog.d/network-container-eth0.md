### Fixed

- **Servers that are containers** (an LXC on Proxmox): their `eth0` is a veth, and it was left out of the network inventory with the host side of the veth pairs. The server had no address, so nothing could be attached to it by IP (Uptime Kuma, OVHcloud, DNS, Coolify). It is now kept as the server's ethernet card.
