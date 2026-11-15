### Added

- **`bin/elio-doctor`**: checks an installation (secrets, databases and their migrations, encrypted data readable with the keys of `.env`, address, SMTP server without sending anything, vulnerability feeds of the fleet) and says what to fix: `docker compose exec elio bin/elio-doctor`.
- **Docker health check** in the image, on `/up`: `docker compose ps` shows whether Elio answers.
- **`docker-compose.caddy.yml`**: Elio behind Caddy, with a Let's Encrypt certificate renewed automatically.
- **Backups** in the README: the commands to save and restore the database and the `storage` volume.

### Changed

- The Docker image is about 100 MB lighter (296 → 194 MB): no test gems, no Tailwind CSS executable (only needed to build the stylesheet), and no duplicated layer for the files of the non-root user.
