### Added

- **What each Docker container reaches of the host**, in the server's Docker tab: privileged containers and containers with the Docker socket mounted are flagged (both give root on the host), published ports show their exposure (every interface or local only), and each container lists its networks and mounts (volumes and host paths, read-only ones marked).

### Changed

- The Docker disk usage (`docker system df`, slow on hosts with many images and volumes) is read every 6 hours instead of at every collection; the last figures are kept in between.

### Upgrading

- Ports, mounts, networks and the privileged / Docker socket flags appear after the next Docker collection of each server.
