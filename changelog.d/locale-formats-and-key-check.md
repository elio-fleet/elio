### Fixed

- **English texts and formats**: the daily digest wrote its highlights with the French “ : ” and its CVE counts without thousands separators; the Uptime Kuma response times always used a decimal comma; the health chart tooltips over 7 and 30 days put the day before the month in English. Two error messages (custom score provider address, unreadable registry authentication) were only in French.

### Changed

- The test suite checks that every translation key named by the code exists, and that every English text is still used; about 75 texts no longer shown anywhere were removed from both languages.
