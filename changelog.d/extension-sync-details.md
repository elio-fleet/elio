### Added

- **Extensions**: each extension shows how long its last sync took, next to when it ran.
- **Extensions**: *Delete the data* (administrators, confirmed, logged) removes what a turned off extension read from its service (probes, OVHcloud resources, DNS records, Coolify resources); its settings stay, and its next sync counts as a first one (no alert for what is already there).
- **OVHcloud**: a consumer key created for a limited time shows its end date in the settings, and a new activity, *Extension key expiring*, announces it two weeks ahead (once per key; it can be sent by the notification channels).

### Changed

- After an extension sync, the health of a server is computed again only when the reasons raised by the extensions changed for it, instead of for the whole fleet.
