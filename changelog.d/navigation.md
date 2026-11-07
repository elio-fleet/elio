### Changed

- **Sidebar in blocks**: Overview and Servers, then "Across the fleet" (Vulnerabilities, Updates, Docker, Ports, Scheduled tasks), "Access" (SSH keys), "Extensions" (Probes, DNS, Hosting, only those enabled), and at the bottom Journal and Settings. A count is coloured only when there is something to handle (fixable vulnerabilities, Docker, failed or late timers). Each entry has its own icon.
- **Renamed pages**: Fleet → Servers, Packages → Updates, Keyring → SSH keys, OVHcloud → Hosting, Activity → Journal (runs: Journal › Runs). Automations moved into the Settings tabs. Server groups left the sidebar: they are a filter of the server list.

### Upgrading

- New addresses: `/ssh-keys`, `/updates`, `/hosting`, `/journal`, `/journal/runs`. The former ones (`/keys`, `/packages`, `/ovh`, `/activities`, `/tasks`) redirect to them, so bookmarks and links in past notifications keep working.
