### Added

- **Repository of each package** in the Packages tab of a server (from `apt-cache policy`): Debian / Ubuntu suites in grey, backports and third-party repositories (Docker, PPAs…) as a badge, packages no repository provides flagged “Not from a repository”, and a filter “Outside the distribution” to list only those.
- **Last package changes** of a server (installs, upgrades, removals read from `/var/log/dpkg.log`, the last 50) under its package list.
- **Compare a package across servers**: its name in the Packages tab opens the fleet search, which now shows the exact name first, the dpkg versions newest first and the repository of each version.

### Upgrading

- The repositories appear after the next packages inventory of each server.
