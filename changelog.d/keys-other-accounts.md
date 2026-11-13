### Added

- **Add a key to any Unix account**: the "Add a key" dialog of a server lets you choose the account: Elio's own (the default), one Elio already read, or another existing account typed in. Another account needs root (or passwordless sudo); its `~/.ssh` and `authorized_keys` are created if missing, owned by the account (700 / 600). Elio never creates an account and never writes through a link nor in a file the account does not own. Temporary accesses work the same way and expire on that account. The keyring key page can add a key to an account of several servers at once.

### Upgrading

- Two new commands that write, both run as root: `keys.append_to_account` and `keys.replace_in_account` (`config/ssh_commands.yml`).
