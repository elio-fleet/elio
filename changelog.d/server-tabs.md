### Changed

- **Server page tabs, in the order of the menu**: Overview · Vulnerabilities · Updates · Services · Docker · Firewall · Scheduled tasks · SSH keys · Probes · DNS · Journal, with the same tab style everywhere and counts coloured by gravity. **Firewall** now holds the ports (public ports against the firewalls first, every listening port folded below), the server's firewall, the OVHcloud network firewall and the suggested rules. **Journal** puts the notes and the history of the server on one timeline (filters: notes, events), with the note form on top. **Services** lists the systemd units only (the containers are in the Docker tab, the Compose files on hover). **Probes** has a Source column. The OVH tab leaves: the service and the IP blocks with their reverse are in the "Hosting" card of the overview.

### Upgrading

- The former tabs redirect: `?tab=ports` → Firewall, `?tab=notes` and `?tab=history` → Journal, `?tab=ovh` → the Hosting card of the overview.
