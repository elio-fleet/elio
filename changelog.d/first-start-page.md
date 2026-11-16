### Added

- **First start page**: a choice of language (it becomes the language of the installation and of the first admin), a warning when `ELIO_HOST` is missing or is not the address the page is open at (links of the emails and notifications), and the problems that would break Elio right after the setup (missing secret, missing database), from `bin/elio-doctor`.
- **Password strength** shown while typing a new password (first start, invitation, password reset).

### Changed

- After the first account is created, Elio goes straight to the mandatory two-factor setup, then to the overview and its getting started list once the backup codes are kept (before: My account).

### Fixed

- The command to install Elio's key on the overview and server pages named the account to log in with twice.
