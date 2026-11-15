### Added

- **Health charts over 7 and 30 days** on the server overview, next to the 24-hour ones (a period switch above the charts; the history Elio already keeps for 30 days, averaged per hour or per 6 hours).
- **Disk trend**: the fullest disk says when it will be full at the pace of the last 7 days ("full in about 12 days", orange under 30 days, red under 7), when it is filling up.
- **Latest events** card on the server overview: the five newest events of the server, with a link to its journal.

### Changed

- The health charts are averaged in the database (one point per 5 minutes over 24 hours), so the page stays light whatever the collection interval.
