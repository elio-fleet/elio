### Added

- **Journal**: filters by minimum severity and by kind, combined with the category, the server and the search, all kept in the address (a filtered journal can be bookmarked or shared).
- **Journal export** as CSV or JSON for an audit, with the filters and the search of the page (50,000 most recent events at most; the JSON says when it was cut). Cells a spreadsheet would run as formulas are neutralised.
- **A permanent link to each event** (`/journal/<id>`): its time in the list opens a page with its kind, severity, date, author, server, account and key, and a link to the same events.

### Changed

- **Journal**: the same event repeated in a row (same kind, server, author and text) shows once with its count ("× 10"); its earlier times unfold below it.
