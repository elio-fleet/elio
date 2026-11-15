### Added

- **Restrictions when adding a key** on a server: allowed source addresses (`from=`), a forced command (`command=`) and no port forwarding, checked strictly and written quoted (a value can never end its option or add another one). A key already on the account keeps its line as it was.
- **Add a key on several accounts** of a server at once: the accounts are checkboxes in the "Add a key" dialog, plus another account typed in; one result per account.

### Changed

- Adding or removing a key from the server's keys tab now writes, checks and reads the list back **on a single SSH connection** (instead of a second one to reload the list); a key not found after its addition, or still there after its removal, is reported as an error.
- Two changes to the keys of the same server (two people, a request and the expiry of a temporary access) now **wait for each other** instead of rewriting `authorized_keys` at the same time.
