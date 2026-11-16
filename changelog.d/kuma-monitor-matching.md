### Added

- **Uptime Kuma**: a monitor can be attached to its server by a **tag** naming it (`server: vm-db1`; the tag name is a setting, `server` by default), before the other rules. Uptime Kuma 2.x only: version 1 does not publish the tags in `/metrics`. Tags now show their value (`server:vmdb1`).
- **Uptime Kuma**: a monitor attached to no server **says why** on the Monitors page: unknown IP, host name not resolved or resolving outside the fleet, rule turned off, no target, detached by hand.

### Upgrading

- The reasons appear after the next synchronization of Uptime Kuma. Monitors tagged `server` in Uptime Kuma 2.x may move to the server their tag names (turn *By a tag of the monitor* off in the extension's settings to keep the previous attachment).
