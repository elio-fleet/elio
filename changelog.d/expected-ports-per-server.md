### Added

- **Expected ports per server**, on top of those of its groups, in the server form: a single server can expose a port without opening it for the whole group.
- **Ignore** next to an unexpected port (Firewall tab, operators and admins): adds it to the server's expected ports in one click, logged in the journal, and the health is recomputed at once.

### Changed

- The listen address of each port says what it means: `0.0.0.0` every IPv4 interface, `::` every interface, `127.0.0.1` this machine only.
