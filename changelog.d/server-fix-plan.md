### Added

- **Fix plan** on the Vulnerabilities tab of a server: every fixable package of the system in one `apt-get install --only-upgrade` command, then the steps most serious first — the system packages by severity, each Compose project (`docker compose pull` and `up -d` of its affected services, in its directory), each image used without Compose — and what to do after (`needrestart -r l` lists the services still running an old library, reboot for a new kernel). Commands to copy: Elio never runs them.
