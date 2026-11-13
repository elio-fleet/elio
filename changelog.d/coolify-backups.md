### Added

- **Coolify database backups**: the backups scheduled in Coolify, database by database, on the Coolify tab (schedule, last successful one, the last 14 runs). A failed backup, no successful one for too long (26 hours by default) or a database with no scheduled backup raise a health reason (each alert can be turned off in the extension); a new failure is logged in the journal and can be notified.

### Upgrading

- The health of every server is computed again after the upgrade (new reasons).
