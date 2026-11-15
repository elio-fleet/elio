### Added

- **Test the connection** in the server form: tries the host, port and user with Elio's key before saving, and shows how to install the key when it is refused.
- **Duplicate** in the menu of a server: a new server with the same port, user and groups.
- A new server gets its **first inventory in the background** as soon as Elio can log in to it, without a click.

### Changed

- The same user on the same host and port can no longer be added twice (the host name's case aside): the form refuses it, and a unique index backs it.

### Upgrading

- If your instance already holds two servers with the same host, port and user, the migration keeps them and skips the unique index, naming them in its output. Delete the duplicate, then run `bin/rails db:migrate:redo:primary VERSION=20261115100000` to add the index.
