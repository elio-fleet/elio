### Changed

- **Docker has its own state, apart from the server's health.** A server whose packages are up to date is no longer "to watch" because of its Docker images: unhealthy or looping containers make the Docker state critical, serious fixable CVEs in the images and images to update make it "to watch". Each change is logged and can be notified (new events "Docker to watch", "Docker in critical state", "Docker healthy again").

### Added

- Settings → Docker: an alert for the **vulnerabilities of the images** (on by default, same severity as the server's vulnerabilities).

### Upgrading

- The health of every server is recomputed at the first automation tick after the update: Docker reasons leave the health. Notification channels that received the health changes now also receive the Docker changes.
