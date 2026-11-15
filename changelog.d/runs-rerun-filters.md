### Added

- **Run again** from a run's page in *Journal → Runs*: on all its servers, or only on the servers that failed (an inventory or keys scan automation is run again as an inventory or keys scan of those servers). Operators for inventories and key scans, admins for automations and key rotation checks; servers already waiting for the same kind of run are left out.
- **Slow servers** of a run flagged ("slow": more than twice the usual duration of the run, at least 10 s), and a *Slowest first* sort of its servers.
- **Filter the runs by kind** (inventory, keys scan, automation…), together with the status filter and the search.

### Fixed

- The result of an automation run ("8/8 servers inventoried") is now shown in the reader's language on the run page, not in the language of the installation.
