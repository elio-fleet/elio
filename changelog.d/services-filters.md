### Added

- **Services tab**: filters (all, active, failed, inactive) and an instant search on the name or the description; the services that start at boot but are not running (one-shot tasks aside) are listed apart; each running service says since when it runs, each stopped one since when it is stopped.

### Changed

- The services inventory reads the details of the loaded services only (`systemctl show`) instead of every unit file on disk (`systemctl list-unit-files`).

### Fixed

- The state of a running service was shown in French in the English interface.
