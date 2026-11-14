### Security

- **Rotation of the database encryption key**: put the former key in `ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS`, a new one in `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, then run `bin/rails elio:reencrypt` (procedure in the README, "Security" section).
- **Permissions-Policy** header (no camera, microphone, location, payment or device API on any page); HSTS documented (sent only when HTTPS is forced).
- **Content Security Policy violation reports** go to Elio itself (`/csp-reports`, rate-limited) and are written to the log; never to an external service.
- Administrators see a notice, which they can hide, when Elio is reached over plain HTTP in production.
- A test checks that the lists of users, extensions, servers and SSH keys never decrypt a secret.
