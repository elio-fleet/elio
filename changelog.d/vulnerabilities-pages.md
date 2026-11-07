### Changed

- **Vulnerabilities page**: the common page header (the feeds' state in the subtitle; "Update the databases" in the "⋯" menu for administrators), tiles that filter the list (all, fixable, serious and fixable), the Systems / Docker images tabs in the common style and the filters on one line. The page of a CVE has a breadcrumb back to the list and its score in a frame of its own.

### Fixed

- An image without a tag no longer shows its whole `sha256:` digest in the list of vulnerabilities by CVE (shortened like the Docker CLI does).
