### Added

- **Import from the extensions**: the import page offers the OVHcloud services and Coolify servers that no Elio server is attached to yet, as a preview to check and edit like a CSV file.
- **Correct a line in error in the import preview**: its name, address, port, user and groups are fields; *Check again* reads them back without starting over.
- **First inventory of the imported servers** in the same click (on by default), on those Elio can already log in to, like a server added by hand.

### Changed

- The import page tells its limits (size and number of servers), lists the `Include` files of an `~/.ssh/config` it did not read, and flags `ProxyJump` / `ProxyCommand` (Elio connects straight to the host).

### Fixed

- Two lines of an import with the same address no longer cancel the whole import: the second one is shown as a duplicate.
- The import errors (empty, too big, not UTF-8, invalid CSV, too many lines) are translated in the interface language.
