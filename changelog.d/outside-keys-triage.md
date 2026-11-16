### Added

- **Outside the keyring**: a key is added to the keyring in one click, under the name of its comment (the form opens instead when it has none or the name is taken), or **tolerated with a reason**: it is no longer reported as unknown, and its reason, author and the servers where it is show in a *Tolerated keys* list, where it can be tolerated no longer. Each unknown key shows since when it is known and a *root* badge when it is on a root account.
- **Unknown key on root**: a new critical activity, *Unknown key on root*, replaces *Unknown key detected* for a key found on a root account, so it is notified right away.

### Upgrading

- Notification channels that received *Unknown key detected* also receive the new *Unknown key on root*.
