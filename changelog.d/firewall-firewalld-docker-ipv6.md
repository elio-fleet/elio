### Added

- **firewalld** is read in the server's Firewall tab (zones, services as their ports, rich rules), after ufw and before nftables / iptables.
- **Docker's DOCKER-USER chain** is read and shown in the Firewall tab: Docker's published ports skip ufw and firewalld, so a port published by a container is flagged as such, or marked as filtered by DOCKER-USER rules when the chain has some. Ports published by containers are also taken from the Docker inventory.
- **IPv4 and IPv6 rules apart** in the Firewall tab, with a warning when the firewall filters only IPv4 (ufw with `IPV6=no`, iptables without ip6tables rules, an nftables `ip` table) while the server listens on a public IPv6 address. The firewall prompt carries the family of each rule and the DOCKER-USER rules.
