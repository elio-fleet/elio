### Added

- **Expected containers** per server (server form): a container of this list that is stopped, paused or missing makes the server's Docker state critical, with its own notification.
- **Docker state details**: a problem about several containers names them ("3 containers unhealthy: api, db, worker"), and the tooltip of the Docker pill lists the problems one per line.

### Changed

- **No Docker alarm just after a reboot**: for ten minutes after the host booted, containers still starting (restarting while waiting for their database, health check not passed yet) are neither looping, unhealthy nor missing. Elio reads the boot time with the Docker inventory (`/proc/uptime`, read-only).

### Upgrading

- The Docker state of every server is computed again on the first automation tick after the update (new wording of the Docker reasons): the new wording alone sends no notification.
