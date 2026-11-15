### Added

- **Updates page by server**: the pending security updates can be grouped by package or by server; each server comes with the `apt-get install --only-upgrade` command that installs all of them (with `sudo` when Elio logs in with another account than root), to copy — Elio never runs it.
- **Reboot flag on the Updates page**: kernel and CPU microcode updates are marked as only applying after a reboot.
- **CSV export of the security updates** (Updates page, actions menu): one line per server and package, with the installed and available versions, the repository and whether a reboot is needed.
