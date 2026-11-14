### Fixed

- **A changed server fingerprint was reported as "SSH access lost: the server refuses Elio's key"** (critical notification), and a closed SSH port showed "Key refused". Only a refused key now marks the access as lost.

### Added

- **"Server fingerprint differs"** in the journal and the notifications (critical), as soon as a server presents another SSH host key than the one Elio knows (a reinstallation, or a machine in between): before, only its acceptance by an administrator was logged. Once per new fingerprint.
