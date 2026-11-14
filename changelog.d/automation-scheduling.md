### Added

- **Hours for an automation** (*Settings → Automations*): a scheduled run starts only within them, for example the packages inventory from 22:00 to 06:00. *Run now* still works at any time.
- **Leave server groups out of an automation**: it runs on the whole fleet (or its groups) except the servers of the groups unchecked, for example no key scan on the lab.
- **Duration of the runs**: each automation shows how long its last run took and the trend of its last 20 runs.

### Changed

- **An unreachable server is no longer tried at every pass** by the inventories: after a failed connection, Elio waits about as long as the server has been down (an hour down, next try in an hour, at most a day). A reachability check that sees it answer again, or *Run now*, tries it right away.
