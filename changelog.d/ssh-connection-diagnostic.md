### Added

- **SSH diagnosis** on the server page: *Diagnose*, next to the SSH check, tests each step of the connection in place — name lookup, SSH port, SSH server banner, host key, login with Elio's key, root access through `sudo -n` — stops at the first one that fails and says what to fix (check the name, open the port, install Elio's key with the commands of the account, review a changed host key, give sudo without a password). Short delays: it answers in seconds even when the server is down.
