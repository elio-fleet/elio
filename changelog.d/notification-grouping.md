### Added

- **Group the notifications by server**: a channel may send one grouped message per type and per server instead of one per type for the whole fleet.
- **Servers affected** at the top of a grouped message ("3 servers affected: web, db, backup"); the signed webhook also gets them (`summary`, `servers`).

### Changed

- The grouping delay of a notification channel is now **any number of minutes** from 0 (send right away) to a day, instead of a fixed list.
