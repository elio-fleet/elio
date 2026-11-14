### Added

- **Installing Elio's key, for any account**: in *Settings → General*, pick root, an existing account with sudo (with the password-less sudoers line to copy) or a dedicated account without sudo (created by the command if missing), and optionally restrict the key to Elio's address (`from="…"`). Elio only shows the commands; it never runs them.
- **Where Elio's key is installed**: the same card lists, server by server, whether the last key scan found Elio's key in its account, whether the SSH login is failing, or whether the keys were not scanned yet.
