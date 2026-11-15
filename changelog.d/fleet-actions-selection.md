### Added

- **Actions on ticked servers**: operators tick servers in the fleet list (one by one or the whole page) to inventory them or scan their keys as one run.
- **Cancel a run**: the servers still waiting in an inventory, a keys scan or a key rotation check can be called off from the run's page; those being read finish.

### Changed

- Inventorying or scanning the keys of the whole fleet now asks for a confirmation first, with the number of servers and the duration expected after the past runs.
- A server already waiting or being read by an inventory (or a keys scan) is left out of a new one instead of being read twice at the same time; started alone, it leads to the run in progress.
