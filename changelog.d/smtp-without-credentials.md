### Fixed

- **Emails through an SMTP relay without credentials** (a local relay, Postfix): every email failed with "SMTP-AUTH requested but missing user name", and "Forgot password" ended on an error page. Without `SMTP_USERNAME`, Elio no longer asks for authentication; an email that cannot be sent is logged and the page answers as usual.
