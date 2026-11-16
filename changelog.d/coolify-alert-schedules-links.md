### Added

- **Coolify links**: a failed backup, a failed or finished deployment in the journal links to the page to look at in Coolify (the database's backups, the deployment); databases and services get their Coolify page too, not only applications.

### Fixed

- **Coolify backups**: a database backed up weekly or monthly is no longer reported late a day after its backup; it is late after the time between two of its scheduled backups (plus 2 hours) when that is longer than the setting.
