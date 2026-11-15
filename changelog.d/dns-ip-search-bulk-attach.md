### Added

- **DNS page: search by IP.** Typing an IP in the search lists every name that leads to it, through CNAMEs and whatever the source, instead of every value that merely contains the text.
- **DNS page: attach in bulk.** Operators tick several records and attach their names at once to a server, to no server, or back to the automatic attachment.

### Changed

- A DNS synchronization only writes what changed: unchanged records keep their row, changed ones are updated in place, the others inserted or deleted.
