### Added

- **Output of a timer's runs** on the Scheduled tasks tab: operators and admins can open the last 50 lines of the journal of the service a systemd timer starts (`journalctl -u`, read-only, read only when opened).
- New event **Scheduled task removed**: an enabled systemd timer, a cron line or a `/etc/cron.*` script that is no longer on the server (a backup that stopped being scheduled, for instance). A users' crontab Elio could not read, or a timer list it could not get, is not taken for a removal.
