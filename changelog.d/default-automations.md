### Changed

- **A new installation collects everything on schedule**: the inventories (system, packages, services and Docker, ports), the reachability check and the key scan are now on by default, next to the health check. Before, they were off: the packages (so the vulnerabilities), Docker, the ports and the keys were only read again when someone asked.

### Upgrading

- An existing installation keeps its own choices. If you never turned them on, enable them in *Settings → Automations*: otherwise the packages, and so the vulnerabilities, are only read when you run an inventory by hand.
