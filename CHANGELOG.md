# Changelog

All notable changes to Elio. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- The interface in **English and French**, and any other language by adding a folder of translations (`config/locales/<language>/`). Each user picks a language in My account; otherwise Elio follows the browser, then the default language of the installation (Settings → General: English on a new installation, French on an existing one). Notification channels have their own language, and an invitation is sent in the language chosen for it.

- **Commands to fix a vulnerability**, in the window of a CVE: the `apt-get` command for the installed packages (after `apt-get update` when the server had not seen the fixed version yet, then a reboot for the kernel), or for an image `docker pull` and the `docker compose pull` / `up -d` of the Compose services that use it; “no fix for now” otherwise. From the fleet page, the commands of each server. Elio never runs them.
- **One DNS for the fleet**: the DNS records of the OVHcloud and Technitium extensions are stored together and attached to the servers the same way (a CNAME of one source follows a name of the other; a manual attachment, by name, applies to every source). One DNS page (`/dns`, filter by source) and one DNS tab on the server page, with the source of each record; the OVH tab and the OVHcloud page link to them.
- **Technitium DNS extension** (read-only API token): every hour, the A, AAAA and CNAME records of its zones, attached to the servers they point to (by IP, by the name a CNAME points to, or by hand). It adds a DNS tab on each server and a DNS page (records outside the fleet, not attached), plus optional alerts for a record pointing outside the fleet and a server without a DNS name. Uptime Kuma monitors are attached through these names too, and the prompt that proposes monitors lists them. Tried on a real Technitium DNS Server 15.6.
- **Grouped notifications**: on each channel, the activities of one type that occur within 10 minutes (adjustable, or 0 for right away) leave as a single message, e.g. “12 × Fixable vulnerability” with their summaries and a link to the activity page filtered on that type. Critical activities are always sent right away. Grouped messages exist for Slack, Discord, email and webhooks (event `activities`, with every activity in `events`). The waiting messages are kept in the database, so a restart loses nothing.
- **Prompts for an AI assistant**, to copy: on the Probes tab of a server (Uptime Kuma), which monitors to create; on its OVH tab, which rules to set in the OVHcloud network firewall. They are generated from the last inventory (system, addresses, services, containers, ports, existing monitors, the machine's firewall, the network firewall rules), in the reader's language, and contain no key, token or password.
- **Notes on a server** (Notes tab): every role leaves notes in Markdown (tables, code, links), with a preview. Their author edits or deletes them, an admin deletes any. The Markdown is rendered without raw HTML or images, and links open without a referrer. A note is logged as an activity (`server_note_added`, which can be notified).
- **SSH keys of every account**: with root (or sudo without a password), the SSH keys tab of a server lists the keys of every account that has a login shell and an `authorized_keys` file, one section per account, and a key can be removed from any of them (Elio's key stays protected). Keys are still added to Elio's login account. The key scan and the unknown keys cover every account; the activities name the account when it is not the login one.
- Keyring: an **Outside the keyring** tab with every key seen on the fleet that matches no keyring key, grouped by fingerprint, with the servers and accounts where it is and “Add to the keyring”.
- Docker page: a **CVE** tab with the vulnerabilities of the images of the fleet, by image then by package, with the servers and containers that run each image.

- Tasks left “queued” or “running” for more than 3 hours by a job that no longer exists (a killed worker, a reset queue) are finished every 15 minutes: their items fail with “Interrupted: the job no longer exists”. A task whose job still waits or runs is never touched.

### Changed

- Fleet page: the actions (refresh the statuses, inventory or scan the keys of the whole fleet, import servers) are in an **Actions** menu; “Add a server” stays a button.
- Server page: the tabs that don't fit go into a **More** menu (the current tab always stays visible), a drop-down list on a phone, in a new order (Overview, Vulnerabilities, Packages, Services, Docker, Ports, Scheduled tasks, SSH keys, extensions, History).
- The Vulnerabilities tab of a server shows the vulnerabilities of the server itself by default (“53 on the server · 12 in 3 Docker images”); a switch, remembered, adds those of its Docker images. Health, the to-do list, the notifications and the daily digest tell the two apart: serious vulnerabilities in images are a warning, fixed by updating the image.
- Health reasons are stored as translation keys and written in the reader's language; the reasons of an existing installation are computed again at the upgrade.

### Fixed

- Signed packages (Secure Boot) were compared with the fixed versions under their own version: `grub-efi-amd64-signed` 1+2.12+9+deb13u2 looked older than grub2's fix 2.12-6, so fixed vulnerabilities were reported, and “not in the repositories yet”. The inventory now reads `Built-Using` and compares the code they sign (grub2, shim, linux, and fwupd-efi — `fwupd-amd64-signed` was wrongly matched with fwupd). Older inventories and the versions offered by apt are converted too.
- Instant searches (Fleet, Packages, Ports, Scheduled tasks, Vulnerabilities, Docker, Probes, OVHcloud, a server's packages and vulnerabilities) no longer lose the characters typed while the results load: only the results are reloaded, the search field keeps its focus.
- The two-factor QR code is black on white with a quiet zone in the dark theme too, so that phones can read it.

## [0.1.0-beta.2] — 2026-11-01

### Fixed

- The Docker image of 0.1.0-beta.1 did not start: production loads all the code at boot, and a file of `lib/` stopped it (`uninitialized constant Elio::Version`). The CI now checks the code loading (`zeitwerk:check`) and starts the built image with PostgreSQL before every release (`bin/smoke-image`).
- Two runs of the same automation could overlap (the run started by the first inventory and one started by hand): two downloads of the vulnerability feeds then replaced the same entries, and one failed. An automation now never runs twice at the same time, "Run now" opens the task already running, and a feed is updated by one download or import at a time.
- `docker-compose.yml`: PostgreSQL is checked over TCP, so that Elio does not start during the first initialization of the database.
- No more Active Storage warning (`image_processing`) when running a command in the image: Elio no longer loads the parts of Rails it does not use.
- A new installation showed no vulnerabilities for a day: the feeds were downloaded at the first start, before any server was added. Now the first inventory of a server on a release that the feeds don't hold yet downloads them at once, and new CVEs get their scores right after, instead of waiting for the next daily (or six-hourly) run.

## [0.1.0-beta.1] — 2026-11-01

The first public version of Elio, the self-hosted fleet manager for Linux servers: agentless, read-only, over SSH. Previously an internal tool named SSHM.

### Fleet and health

- Fleet list and grid, filters by group, system, state, address or host name; overview of what needs attention, most serious first.
- Health of each server: load, memory, swap, disks and inodes, reboot required, failed services, clock sync, pending (security) updates; thresholds in the settings; 30 days of history with 24-hour charts.
- Reachability and SSH checks, host keys pinned on first connection (a change waits for an administrator).
- Server groups (with expected public ports), import from CSV or `~/.ssh/config`.

### Inventory

- System (distribution, kernel, virtualization, end-of-support date), network addresses (WireGuard and other VPNs), host name.
- Packages (dpkg with their source package, snap), searchable across the fleet.
- systemd services; Docker containers grouped by Compose project.
- Docker: container health, restart loops, long-stopped containers, CPU and memory, images (age, size, unused, `latest`), new versions published on the registries (Docker Hub, GHCR, Quay, private ones with read-only tokens).
- Scheduled tasks: crontabs and systemd timers in plain words, failed or late timers.
- Listening ports with their process, service or container; firewall state (ufw, nftables, iptables); suggested ufw rules to copy (never applied).
- Every command run on the servers is in `config/ssh_commands.yml`, read-only except the SSH key ones.

### Vulnerabilities

- CVEs of the packages from the Debian Security Tracker and Ubuntu's OSV data, downloaded every day for the releases of the fleet (or imported by hand on a closed network), matched with the inventory with dpkg's version comparison; the running kernel counts.
- Grouped by package with the update to make, whether the server's repositories already offer it, and the apt command to copy; or listed by CVE, with search.
- Scores from NVD, Red Hat, CVE.org and CISA, or custom providers (JSON API or web page); exploitation from EPSS and CISA KEV; coloured scores; the score gives the severity of the CVEs the distribution did not rate.
- CVE detail: description, score and CVSS vector of each provider, packages and versions, other servers touched.
- Docker images: Trivy or Grype when installed, else the packages of the image matched by Elio.
- Fleet page by package or by CVE; alerts from a chosen severity.

### SSH keys

- Shared keyring (people and machines); add or remove a key on a server, for good or for a limited time (expiring on its own, even if Elio is down); unknown keys detected; keys found on servers added to the keyring in one click.
- Rotation of Elio's own key without downtime.

### Alerts, automation, team

- Activity log; notifications to Slack, Discord, email or signed webhooks, chosen per kind of activity; daily digest.
- Scheduled collections on the whole fleet or per group; background tasks followed live; Mission Control for administrators.
- Extensions, read-only: Uptime Kuma (monitors attached to servers) and OVHcloud (IPs, network firewall, DNS records, services).
- Roles (admin, operator, read-only), invitations, two-factor authentication (mandatory by default for admins and operators), session timeout and lockout, ⌘K search, light and dark themes, French interface.

### Installation

- Docker image `ghcr.io/elio-fleet/elio` (amd64, arm64) and `docker-compose.yml`; Kamal configuration.
- Secrets of an installation from environment variables, generated by `bin/elio-keys`.

### Upgrading from SSHM

- Rename the databases (`sshm_*` → `elio_*`) and the Kamal volume (`sshm_storage` → `elio_storage`); keep `RAILS_MASTER_KEY` if your secrets are in Rails credentials.

### Known limits

- Full inventory for Debian and Ubuntu only; Ubuntu not yet tried on a real server.
- Uptime Kuma and OVHcloud built on recorded API answers, not yet tried on real accounts.
- Image CVEs without Trivy or Grype: Debian and Ubuntu based images only.
- The interface is in French.

[Unreleased]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.2...HEAD
[0.1.0-beta.2]: https://github.com/elio-fleet/elio/releases/tag/v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/elio-fleet/elio/releases/tag/v0.1.0-beta.1
