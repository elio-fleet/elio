### Added

- **Out-of-memory kills** in the health: a server whose kernel killed processes for lack of memory in the last 24 hours needs attention ("3 processes killed for lack of memory in 24 h"). Read from the kernel's counter (`/proc/vmstat`), no root needed.

### Changed

- The health check runs the apt simulation (pending updates) only when the package database or the package lists changed since the last one, or after 6 hours: it was the costly part of a check that runs every 15 minutes.

### Fixed

- The files a container runtime mounts from the host (`/etc/hosts`, `/etc/resolv.conf`…) are no longer listed as disks: inside a container, the "fullest disk" could be `/etc/hosts`.
