### Fixed

- **"Container restarting in a loop" after a reboot**: a container that restarted three times at boot while waiting for its database, then stayed up, was reported as looping (Docker critical, critical notification), and so was any old container after a `docker restart`. A loop is now at least three restarts since the previous collection on a container up for less than two minutes (or in the "restarting" state).
