### Added

- **Configuration** in Settings → General: what Elio read from its environment variables (address, HTTPS, emails, limits, feed mirrors), with the checks of `bin/elio-doctor` that need no network. Secret values are never shown, only "set" or "not set"; a mirror URL is shown without its credentials.

### Changed

- A whole-number variable that cannot be read (`ELIO_PARALLEL_LIMIT`, `ELIO_ACTIVITY_RETENTION_DAYS`, `SMTP_PORT`) now stops Elio at start with a message naming the variable.

### Upgrading

- `ELIO_ACTIVITY_RETENTION_DAYS` with a value that is not a whole number (`1y`) was read as `0`, keeping the activity log forever; Elio now refuses to start with it: set a number of days.
