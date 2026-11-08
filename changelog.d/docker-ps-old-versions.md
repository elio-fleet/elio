### Fixed

- **Services**: the containers of a server running Docker older than 20.10 (e.g. 19.03) are read again instead of "Docker containers unreadable: Template parsing error … can't evaluate field State". Their state now comes from the status that every Docker version prints.
