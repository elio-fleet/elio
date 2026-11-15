### Added

- **Extend a temporary access**: a *Temporary accesses* page per server (linked from the SSH keys tab and from the expiry of each key) lists the accesses in progress, each extendable by a chosen duration from its current end. Only the `expiry-time` option of the key's line changes on the server: its other options and comment stay as they are.
- **Reminder before the end** of a temporary access: a new *Temporary access ending soon* activity, recorded once 10 minutes before the end of accesses longer than 30 minutes, that notification channels can subscribe to. Extending an access is logged too (*Temporary access extended*).
- **History of temporary accesses** per server: the 50 most recent ended accesses, with their start, end, how they ended (expired, or removed / replaced before) and how many times they were extended.
