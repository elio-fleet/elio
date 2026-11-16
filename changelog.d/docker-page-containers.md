### Added

- **Containers tab** on the Docker page: every container of the fleet with its state, server, Compose project, published ports and host access; the tiles filter the ones to watch, those that are root on the host (privileged or Docker socket) and those with a port published on every interface; search by container, image or project.
- **Unused images** on the Docker page: by server, how many images no container uses, their size and the space `docker system df` says can be reclaimed.

### Changed

- The images of the Docker page show their creation date and size, and sort by CVEs, age or size; an image no container uses names the servers that keep it.
