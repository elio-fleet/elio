### Added

- **Backup codes can be downloaded** as a text file when two-factor authentication is turned on or the codes are regenerated.
- **Email when a backup code is used** to sign in (when outgoing emails are set up): date, IP address, codes left, what to do if it was not you.
- **Unlock an account** before the end of its lock: *Settings → Users* shows locked accounts and an *Unlock* action (logged in the journal).

### Changed

- When two-factor authentication is mandatory for a role, its setup page opens at once (instead of *My account* and a message).
- The sign-in error states the lock rule (10 failed attempts in a row lock an account for 15 minutes), the same for every email; a wrong 2FA code shows the attempts left.

### Security

- Typing the right password again no longer resets the failed attempts of an account with two-factor authentication: wrong codes keep counting until a code is right, so the lock really limits the guesses of the code.
