### Added

- **Dry run of a key rotation** (Settings → General → key menu → « Simulate a rotation »): checks every server read-only — reachable, Elio's key accepted, `~/.ssh/authorized_keys` writable by the login account — and lists, as a task, the servers where a rotation would fail. Nothing is written on the servers.
- **Reminder to rotate Elio's key** once it is more than a year old, on the settings page, with a link to the dry run.
- **Resume an interrupted rotation**: a rotation whose job was lost (Elio restarted) shows that it has stopped moving and can be resumed; it goes on with the servers not done yet instead of redoing them.

### Changed

- A key rotation opens two connections per server instead of three (the login check and the removal of the old key share the connection opened with the new key), and both hold the server's key lock, so a rotation never rewrites `authorized_keys` at the same time as another change of that server's keys.
- A rotation run only handles the servers it has not done yet: a job started again after a restart no longer redoes every server, and a server added during the rotation gets the new key before the old one is deleted.
