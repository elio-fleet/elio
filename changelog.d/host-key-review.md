### Added

- **Changed host keys page** (Fleet → a server's SSH warning → "Review all changed host keys", admins only): every server whose host key changed, with the old and new fingerprints, to trust several new keys at once after a planned reinstall. Elio contacts each checked server again and accepts only the fingerprint shown; each acceptance is logged in the journal.
- The SSH warning of a server shows the type of each key next to its fingerprint and the exact `ssh-keygen -lf` command to read the new one on the server's console.
- **A key of a new type is told apart from a changed key**: when a server presents a key of a type Elio had not pinned (for instance RSA instead of Ed25519), the warning, the journal and the notifications say so. It stays blocked until an administrator accepts it.

### Fixed

- Trusting a new host key that the server no longer presented (or when the server did not answer) removed the old pin, so the next connection accepted any key. The old pin now stays and the server stays blocked.
