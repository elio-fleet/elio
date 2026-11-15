### Added

- **Health thresholds per group and per server**: a group (production stricter than staging) or a server can set its own disk, inodes, memory, swap and load thresholds in its edit form; blank fields keep the inherited ones, shown in grey. A server in several groups takes the strictest. Meters and charts follow the thresholds of each server.
- **Inodes and swap thresholds of their own** in *Settings → General*. The swap is a new health reason, not watched until you set its thresholds.
- **Minutes beyond a threshold before it counts** for the load and the memory (*Settings → General*, 0 by default: at once), so that a short peak raises nothing.

### Upgrading

- The inodes thresholds start with the values of your disk thresholds, as before. The health of every server is computed again on the first automation tick.
