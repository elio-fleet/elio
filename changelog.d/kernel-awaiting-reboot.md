### Fixed

- **Kernel waiting for a reboot** on the Vulnerabilities tab of a server: when the fixed kernel is already installed but the server still runs the old one, the kernel shows "installed, reboot needed" (with both versions) instead of "not in the repositories yet", and the fix plan and the CVE window ask for a reboot instead of an `apt-get update` and a reinstall that fixed nothing.
- Opening the CVEs of one package from the Vulnerabilities tab no longer switches the remembered view to "By CVE" for good: the package view stays the default until the toggle is used.
