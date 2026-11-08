# Changelog

All notable changes to Elio. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.1-beta] — 2026-11-08

Three fixes after 0.4.0-beta: Docker older than 20.10, the OVHcloud firewall warning for IPv6 blocks, and the Network card of the server page.

### Upgrading from 0.4.0-beta

- No migration. The health of every server is recomputed at the first automation tick, which removes the "OVH network firewall disabled" warnings of IPv6 blocks.
- One command on the servers changes: the `docker ps` format no longer asks for `{{.State}}` (the state is read from `{{.Status}}`). Nothing to change if you did not override it in `config/ssh_commands.yml`.

### Changed

- **Server page, Network card**: the scope of each address is an icon (a globe for public, a lock for private), with its meaning on hover, so the card no longer overflows with long IPv6 addresses; long addresses wrap.
- **VPN interfaces** are shown as "VPN" (WireGuard, OpenVPN and other tun / tap interfaces, IP tunnels), the exact kind on hover; the Uptime Kuma probes say "via 10.8.0.100 · wg0 (VPN)".

### Fixed

- **Services**: the containers of a server running Docker older than 20.10 (e.g. 19.03) are read again instead of "Docker containers unreadable: Template parsing error … can't evaluate field State". Their state now comes from the status that every Docker version prints.
- **OVHcloud**: the "OVH network firewall disabled" health warning no longer shows for IPv6 blocks. OVHcloud has no network firewall for IPv6, so these blocks always came back without one; the health of every server is computed again after the upgrade, so the warning goes away by itself. The ports reachable in IPv6 are still reported by the optional "IPv6 not covered" warning.

## [0.4.0-beta] — 2026-11-08

A new interface, the same on every page, and Docker with a state of its own. From this version on, versions are numbered 0.4.0-beta, 0.5.0-beta… (a fix: 0.4.1-beta); the beta ends with 1.0.0.

### Upgrading from 0.1.0-beta.4.1

- Migrations run at start-up. The health of every server is recomputed at the first automation tick: the Docker reasons leave the health and become the Docker state. Notification channels that received the health changes also receive the Docker changes.
- Pages and menus are renamed (Fleet → Servers, Packages → Updates, Keyring → SSH keys, OVHcloud → Hosting, Activity and Tasks → Journal) and have new addresses: `/ssh-keys`, `/updates`, `/hosting`, `/journal`, `/journal/runs`. The former addresses (`/keys`, `/packages`, `/ovh`, `/activities`, `/tasks`) redirect to them, so bookmarks and links in past notifications keep working.
- Server page: the former tabs redirect (`?tab=ports` → Firewall, `?tab=notes` and `?tab=history` → Journal, `?tab=ovh` → the Hosting card of the overview).
- No new command on the servers.

### Added

- **Docker has its own state, apart from the server's health.** A server whose packages are up to date is no longer "to watch" because of its Docker images: unhealthy or looping containers make Docker critical; serious fixable CVEs in the images and images to update make it "to watch". The whale shows next to the health badge (red or orange with the number of Docker problems, grey when Docker is fine), on the server page and in the server list (filters "Docker to watch", "Docker critical"). Each change is logged and can be notified ("Docker to watch", "Docker in critical state", "Docker healthy again").
- Settings → Docker: an alert for the **vulnerabilities of the images** (on by default, same severity as the server's vulnerabilities).
- **Design system**: shared components for every page (page header with a "⋯" menu, clickable tiles, one-line filters, tabs, panels, "to handle" lists, journal entries, empty states, form sections, a single Save bar). The `/design` page (outside production) shows each of them with its rule; a system test checks the rules on every main page (one title, at most one primary action, no sideways scroll at 1024 and 1280 px).

### Changed

- **Sidebar in blocks**: Overview and Servers; "Across the fleet" (Vulnerabilities, Updates, Docker, Ports, Scheduled tasks); "Access" (SSH keys); "Extensions" (Probes, DNS, Hosting, only those enabled); Journal and Settings at the bottom. A count is coloured only when something needs attention. Server groups left the sidebar: they are a filter of the server list.
- **Overview**: the tiles open the matching list; "To handle" is grouped by gravity (Docker included), each line naming its action ("See the disks", "Test the connection", "See the fixes"…) and the servers concerned; on the right, the recent activity, the groups and their servers to handle, the temporary accesses while there are some. An empty fleet shows only the getting started guide.
- **Server list**: one line of filters (search, group, system, state chips with their count), clickable tiles, the group under the name, no probe column, long notes cut with the full text on hover; the fleet actions (inventory, key scan, import, groups) in the "⋯" menu.
- **Server page**: a compact overview (the machine, its addresses and its hosting on the left; what to handle, each reason with its action, and the health with 24-hour trends on the right); port, SSH and Docker on one line; Delete in the "⋯" menu. **Tabs by function, in the order of the menu**: Overview · Vulnerabilities (system only) · Updates · Services (systemd only) · Docker (Containers, Images and Vulnerabilities sections) · Firewall (with the ports) · Scheduled tasks · SSH keys · Probes (with their source) · DNS · Journal (notes and history on one timeline). The OVHcloud service and IP blocks are in a Hosting card of the overview.
- **Fleet pages** (Vulnerabilities, Updates, Docker, Ports, Scheduled tasks): the common header, tiles that filter, one filter bar, the same tabs. Vulnerabilities in two tabs, Systems and Docker images; the page of a CVE has a breadcrumb. Docker lists the images with fixable CVEs first, with their severity. Updates searches an installed package.
- **Extensions** (Probes, DNS, Hosting), **SSH keys** and **Journal** (events and runs as two tabs) on the same layout; one style of filter chips everywhere.
- **Settings**: a menu on the left, **one Save per page** (a bar that appears when a field changes): General (language, health thresholds, AI instructions together), Automations (every automation at once, as a table), Vulnerabilities (alerts and score colours). Dangerous actions (regenerating Elio's key, deactivating a user…) are in "⋯" menus, behind a confirmation. The role of a user saves when it is changed.
- **Forms, My account and the sign-in pages** use the same header, cards and sections; the sign-in pages show the logo and the version.
- The Docker icon is the Docker whale.

### Fixed

- The table of scheduled tasks fits the page (the state comes first, long schedules wrap, long commands are cut).
- An image without a tag is shown by its short digest (`sha256:` + 12 characters) instead of the whole digest overflowing the next column.
- Hosting without any OVHcloud service says the account has none, instead of "No resource matches".

## [0.1.0-beta.4.1] — 2026-11-07

### Upgrading from 0.1.0-beta.4

- Nothing to do: no migration, no new setting, the same commands on the servers. Replace the image and restart.

### Added

- For contributors: `bin/rails dev:demo` fills a development database with the fictitious fleet of the screenshots (7 servers, inventories, Docker, vulnerabilities, extensions, DNS), to try Elio without servers; it refuses a database that already has servers unless `FORCE=1`.

### Changed

- For contributors: each pull request describes its change in a file of `changelog.d/` instead of editing `CHANGELOG.md`; `bin/changelog` assembles them at release time (see `changelog.d/README.md`).
- Dependencies: `solid_queue` 1.7.1 (more resilient background jobs), `json` 3.1.0, `rack-test` 2.3.0 and small updates.

### Fixed

- **Confirmations**: a confirmation opened right after a cancelled one could take the answer of the cancelled one (the action was then not done).
- **Accents in server outputs**: the outputs of the commands are read as UTF-8 text (bytes that are not UTF-8 are replaced). With the updated `json` gem of this version, an accent in a scheduled task, a file or a message would otherwise have broken the collection of the server.
- **Uptime Kuma 1.x**: the probes were not read at all (Uptime Kuma 1.x gives them no id in `/metrics`); they are now identified by their name. A probe without answer no longer shows a response time of -1 ms.

### Security

- `net-ssh` 7.3.9: host keys marked `@revoked` in a known_hosts file are refused (Elio's own known_hosts file never holds such lines, so no change in practice).

## [0.1.0-beta.4] — 2026-11-06

### Upgrading from 0.1.0-beta.3.1

- Change the image tag to `0.1.0-beta.4` (or pull `beta`) and restart: the migrations run at start (instructions of the prompts, SSH sources, firewall options) and nothing changes until you use the new settings. The first background tick then computes the health of every server again.
- The image is now built on **Debian 13 (trixie) with Ruby 3.4.12** (it was Debian 12.10): same size, nothing to do. Keep the same `.env` (or environment variables) as before.
- The OVHcloud network firewall, its anti-DDoS and the firewall prompt moved from the **OVH** tab to the new **Firewall** tab; the suggested ufw rules moved from the **Ports** tab to it.
- New tab *Settings → Firewall*: the sources allowed to reach SSH (none by default: the suggested rules open SSH to everyone, as before) and two options, off by default.

### Added

- **Gandi extension** (DNS source): the A, AAAA and CNAME records of the domains served by Gandi LiveDNS go into the DNS of the fleet (attached to the servers, common DNS alerts, DNS page and tab), with a personal access token that has read rights only (`GET` only, `Authorization: Bearer`). The domains are listed with their expiry date and auto renewal, with an optional alert when one expires soon. Tested against a fake API built on the examples of the Gandi documentation only (no real account yet).
- **Firewall tab** on the server page: the server's own firewall (ufw, nftables or iptables, with its rules), the OVHcloud network firewall of its OVH IPs (rules, anti-DDoS), the public ports with the verdict of each firewall side by side, the ufw rules to copy and the prompt for an AI. The Ports and OVH tabs link to it.
- **SSH open only to some addresses** in the suggested firewall rules: a named list of sources (*Settings → Firewall*, e.g. "Elio → 203.0.113.5", "Coolify → …"), and each group of servers can choose some of them. The ufw rules then allow SSH only from them (with a reminder that Elio's own address must be among them), the firewall prompt asks to restrict SSH to them, and the Firewall tab says where SSH is open from. Without any source, nothing changes.
- **IPv6 and the OVHcloud network firewall**: it filters only IPv4, so the Firewall tab shows the public ports listening in IPv6 as "Not covered (IPv6)", with a warning, and the prompt says so. Optional health reason (*Settings → Firewall*, off by default).
- **Block all the incoming IPv6** in the suggested ufw rules (option, off by default): the ports are allowed from IPv4 only, so the default policy denies every incoming IPv6 connection.
- **Instructions for the prompts** (*Settings → General → Prompts for an AI*): your own text, added at the end of the prompt, e.g. "For the SSH port, always put the rules last". The firewall prompt now covers the server's firewall, and the OVHcloud one when the extension is on.

### Changed

- After an upgrade, the health of every server is computed again by the first background tick when its rules changed (instead of a migration that could run before the columns it needs).
- **The Docker image is built on Debian 13 (trixie) with Ruby 3.4.12, and takes the Debian security updates at every build.** The previous image (Debian 12.10, never updated) carried 89 CVEs that Debian had fixed (openssl, gnutls28, glibc, pcre2, systemd, pam, libcap2, apt, gnupg2, libgcrypt20…): none is left. The CI fails when a security update is pending in the image, and Dependabot proposes the new base images.

### Fixed

- **Faster vulnerability pages** on a big fleet: the vulnerabilities are aggregated in the database instead of being loaded one by one (by package: 1.4 s → 0.5 s on 69,000 rows; by CVE: 0.26 s → 0.16 s), and the *CVE* tab of the Docker page loads the packages of an image when it is unfolded (1.5 s and 18 MB of HTML → 0.1 s and 72 KB).
- The default section of the extension settings read “Connexion” in the English interface.

## [0.1.0-beta.3.1] — 2026-11-06

A fix for upgrades to 0.1.0-beta.3.

### Upgrading

Change the image tag to `0.1.0-beta.3.1` (or pull `beta`) and restart: a migration converts the health reasons of every server, from the inventory already stored (no SSH). Nothing else to do, from 0.1.0-beta.2 or 0.1.0-beta.3.

### Fixed

- Upgrading from 0.1.0-beta.2: the health reasons of the servers were not converted to the new format (the migration ran before the columns it needed, and failed for every server), so they stayed in French until the next health check. They are now converted by the last migration.

## [0.1.0-beta.3] — 2026-11-06

### Upgrading from 0.1.0-beta.2

- The database migrations run at start, as usual. They move the DNS records of the OVHcloud extension into the new DNS of the fleet, and turn its DNS alerts into the common ones of *Settings → Extensions → DNS*: an alert on in the extension stays on, and the records already reported are not reported again.
- Each notification channel now groups its non-critical notifications over 10 minutes. Set *Group the notifications* to *No* on a channel to keep the previous behaviour.
- To see the SSH keys of every account of a server, Elio needs root (log in as root, or password-less `sudo`); without it, nothing changes.

### Added

- The interface in **English and French**, and any other language by adding a folder of translations (`config/locales/<language>/`). Each user picks a language in My account; otherwise Elio follows the browser, then the default language of the installation (Settings → General: English on a new installation, French on an existing one). Notification channels have their own language, and an invitation is sent in the language chosen for it.

- **Commands to fix a vulnerability**, in the window of a CVE: the `apt-get` command for the installed packages (after `apt-get update` when the server had not seen the fixed version yet, then a reboot for the kernel), or for an image `docker pull` and the `docker compose pull` / `up -d` of the Compose services that use it; “no fix for now” otherwise. From the fleet page, the commands of each server. Elio never runs them.
- **One DNS for the fleet**: the DNS records of the OVHcloud and Technitium extensions are stored together and attached to the servers the same way (a CNAME of one source follows a name of the other; a manual attachment, by name, applies to every source). One DNS page (`/dns`, filter by source) and one DNS tab on the server page, with the source of each record; the OVH tab and the OVHcloud page link to them. A name whose records differ between sources (split horizon) is flagged “differs by source” and can be filtered; ⌘K finds who has a DNS name. The DNS alerts are common to every source, in *Settings → Extensions → DNS*: record pointing outside the fleet (once per name and IP, whatever the source), server without a DNS name (only if no source has one, with groups to ignore), and, optionally, a name that differs between sources. The checkboxes of the two extensions are carried over. The fleet search and ⌘K find a server by one of its DNS names.
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

- Reading the keys of other accounts as root no longer follows a symbolic link nor reads a file the account does not own: a user could otherwise make Elio show (and remove keys from) another account's file, such as root's.
- A notification added while its batch was being sent could be lost; it now opens a new batch.
- The commands to fix a kernel vulnerability no longer include `reboot` in the block to copy (a note says when to reboot).
- Texts left in French in the English interface: “unexpected” ports, “fixable”, the OVH anti-DDoS mode, the sections of the extension settings, the vulnerability counts by severity.

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

[Unreleased]: https://github.com/elio-fleet/elio/compare/v0.4.1-beta...HEAD
[0.4.1-beta]: https://github.com/elio-fleet/elio/compare/v0.4.0-beta...v0.4.1-beta
[0.4.0-beta]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.4.1...v0.4.0-beta
[0.1.0-beta.4.1]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.4...v0.1.0-beta.4.1
[0.1.0-beta.4]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.3.1...v0.1.0-beta.4
[0.1.0-beta.3.1]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.3...v0.1.0-beta.3.1
[0.1.0-beta.3]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.2...v0.1.0-beta.3
[0.1.0-beta.2]: https://github.com/elio-fleet/elio/releases/tag/v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/elio-fleet/elio/releases/tag/v0.1.0-beta.1
