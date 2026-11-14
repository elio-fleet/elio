### Security

- **Keys of another account written as that account**: the authorized_keys of an account other than Elio's is now read and written as that account (`runuser`), root only finds it. Before, root wrote it after checking it was not a link: in between, the account could have replaced its file by a link to a system file. Elio's own account was never concerned.

### Upgrading

- `keys.read_accounts`, `keys.append_to_account`, `keys.replace_in_account` and `keys.remove_from_account` use `runuser` (util-linux, present on Debian and Ubuntu).
