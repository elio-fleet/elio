### Changed

- **Vulnerabilities page in two tabs**: "Systems" (the packages of the servers, by default) and "Docker images", each with its own tiles and counts. The "Origin" list is gone; links with `?origin=image` open the Docker images tab.

### Fixed

- An image without tag is shown by its short digest (`sha256:` + 12 characters) in the vulnerability lists, instead of the whole digest overflowing the next column.
