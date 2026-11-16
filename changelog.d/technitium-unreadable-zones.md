### Added

- **Technitium DNS: zones not read** are named in the sync summary and listed in the extension settings with the reason: a zone chosen in the settings that the token does not see (a typo, a deleted zone, or no View permission on it), or a zone whose records were refused. Testing the connection also names the chosen zones the token does not see.

### Changed

- **Technitium DNS**: a zone whose records cannot be read no longer fails the whole sync: its previous records are kept (no false "outside the fleet" or "without a DNS name" alerts), and the sync fails only when every zone is refused.
