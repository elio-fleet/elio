### Added

- **Detailed health on `/up`** for a monitoring tool: with `ELIO_HEALTH_TOKEN` set, `/up` called with `Authorization: Bearer <token>` answers in JSON whether the database answers, a job worker runs and the automations ran lately (with Elio's version), and **503** when one of them fails, so a stopped job worker no longer goes unnoticed. Without the token, `/up` stays as before: 200 as soon as Elio runs, nothing else revealed. The README explains the Uptime Kuma monitor to create for Elio itself.
