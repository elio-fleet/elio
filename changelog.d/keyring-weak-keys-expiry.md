### Added

- **Weak keys flagged**: a DSA key, or an RSA key under 3072 bits, shows a *Weak key* badge in the keyring, on "My account", in the SSH keys tab of a server, in the *Outside the keyring* list, with the reason and what to use instead on the key's page and in its details. The size of an RSA key is shown next to its type.
- **Expiry date of a keyring key**: an optional date on each key, shown as *Expires <date>* in the 14 days before it and *Expired* after. A new *Keyring key to rotate* activity is recorded once per date, 14 days before (or as soon as a past date is set), that notification channels can subscribe to.
