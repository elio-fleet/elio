### Added

- **Restrictions of each key** in a server's keys tab: allowed source addresses (`from=`), forced command, `restrict` and expiry (`expiry-time`, "expired" once the server refuses it) as badges on the row; every option explained in the key details.
- **Accounts with a login shell and no key** (no `authorized_keys` file) listed under the keys of a server read with root, to spot dormant accounts.
- **Other key files read by the SSH server**: with root, the files named by `AuthorizedKeysFile` (`sshd -T`, OpenSSH's default `~/.ssh/authorized_keys2` otherwise) are read as their account and their keys shown under the account, with a warning. Elio does not change these files.

### Security

- A line of an `authorized_keys` file can no longer pass for a section of the output Elio parses when it reads every account.
