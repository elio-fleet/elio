### Added

- **Partial collection, explained**: the server overview lists what the inventory could not read, each cause once with the categories it affects (links to their tabs) and, without root access, how to get a full collection. The *Partial* badges of the tabs link to it.
- **Root access in the connection test**: "Test the connection" in the server form also says whether Elio will be root, use password-less sudo or have no root access (and what will then be partial).

### Changed

- Without access to Docker (neither root nor the docker group), Packages, Services and Docker now give the same short reason instead of three copies of Docker's error.
