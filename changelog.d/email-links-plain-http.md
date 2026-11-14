### Fixed

- **Links in the emails of an installation tried over plain HTTP** (`ELIO_FORCE_SSL=false`): the password-reset and invitation links started with `https://` and led nowhere. They now follow the installation: `http://` when HTTPS is not forced.
