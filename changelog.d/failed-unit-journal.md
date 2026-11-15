### Added

- **Journal of a failed unit** on the Services tab: operators and admins can open a failed unit to read the last 50 lines of its journal (`journalctl -u`, read-only, read only when you open it), next to the command to restart it yourself, ready to copy (Elio never runs it).
- A unit that failed while the server was starting says so ("failed at server startup") instead of only since when it failed.

### Changed

- A failed unit that recovers while others stay failed no longer sends a "new problem" event: only a unit that newly fails does.
