### Added

- **Password changed email**: changing a password (My account, a reset by email, a change asked by an administrator) sends an email to the owner of the account, in their language, so a change they did not make is noticed at once. The other sessions and "remember me" cookies of the account are signed out.

### Changed

- **Forgot password without an email server**: the sign-in page says that no email server is configured and to ask an administrator, and the reset page sends back there instead of pretending to send a link.
- **Password reset email sent in the background**: the request no longer waits for the SMTP server, and answers in the same time whether the account exists or not.

### Security

- **Password reset rate limit per email too**: at most 5 requests per email within 10 minutes, whatever the IP, on top of the 5 per IP.
