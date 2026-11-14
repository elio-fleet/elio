### Fixed

- **Uptime Kuma 1.23 and 2.0 do not publish the uptime** in `/metrics`: the "Uptime 24 h · 30 d" column only showed dashes and the uptime alert could never fire. The column is now hidden when the instance does not publish it, and the setting of the alert says so.
