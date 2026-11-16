### Added

- **Email on a sign in from a new browser**: when email is configured, the owner of an account is told (in their language, with the date, IP address and browser) the first time it signs in from a browser it never used. The browser is recognized by an encrypted cookie; nothing changes on the sign-in page, so it reveals nothing to whoever signs in.

### Changed

- The 30-minute session expiry after inactivity is now covered by tests (password, second factor, "remember me").
