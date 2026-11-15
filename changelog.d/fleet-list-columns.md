### Added

- **Fleet list: sort by a column.** A click on Server, Load, Memory, Disk or Updates sorts the list (the biggest first, a second click reverses it; servers without an inventory stay last). The order is kept by the filters and in the address.
- **Fleet list: choose your columns.** The "Columns" menu hides the system, load, memory, disk, updates or notes column. The choice is saved on your account, so it follows you to another browser.
- **Fleet list: export to CSV** (⋯ menu), following the filters and the order of the page, every server (not only the current page): address, groups, system, health state and its reasons, Docker state, load, memory, disk and updates. Available to every role; a cell that a spreadsheet would run as a formula is neutralised.

### Fixed

- **Fleet list: the table fits its card on a desktop screen.** At 1,400 px wide the last column (refresh and edit) was cut: the notes now take the room left and are shortened (the full text on hover), long addresses too, and the System column shows from 1,536 px.

### Upgrading

- A migration adds the `preferences` column to `users` (the columns each user hides); nothing to do.
