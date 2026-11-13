<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/logo-dark.svg">
    <img src="docs/brand/logo-light.svg" alt="Elio" height="64">
  </picture>
</p>

<p align="center">
  <strong>The self-hosted fleet manager for your Linux servers.</strong><br>
  Health, inventory, vulnerabilities, Docker and SSH keys — agentless, read-only, over SSH.
</p>

<p align="center">
  <a href="https://github.com/elio-fleet/elio/actions/workflows/ci.yml"><img src="https://github.com/elio-fleet/elio/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/elio-fleet/elio/releases"><img src="https://img.shields.io/github/v/release/elio-fleet/elio?include_prereleases&label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License: AGPL-3.0"></a>
  <a href="https://github.com/elio-fleet/elio/pkgs/container/elio"><img src="https://img.shields.io/badge/image-ghcr.io%2Felio--fleet%2Felio-4f46e5" alt="Docker image"></a>
</p>

<p align="center">
  <a href="https://elio-fleet.github.io/elio/">Website</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#features">Features</a> ·
  <a href="#extensions">Extensions</a> ·
  <a href="#security">Security</a> ·
  <a href="README.fr.md">Français</a>
</p>

![The fleet in Elio](docs/screenshots/en/fleet.png)

Elio watches a fleet of Debian and Ubuntu servers from one place: which ones are healthy, what runs on them, which packages are vulnerable and how to fix them, who has an SSH key on them. Nothing to install on the servers: Elio logs in with its own SSH key and runs a short list of **read-only commands**, all written in one file you can review — [`config/ssh_commands.yml`](config/ssh_commands.yml).

> **Beta.** Elio is young (`v0.4.1-beta`). It is used on real servers, but expect rough edges, and read the [known limits](#known-limits).

## Features

| | |
|---|---|
| **Health** | Load, memory, swap, disks and inodes, reboot required, failed services, clock sync, pending updates — with thresholds you set and 30 days of history. The health of a server covers its system and packages; **Docker has its own state** next to it (the whale). |
| **Inventory** | System and end-of-support date, network addresses (WireGuard included), packages (dpkg, snap), systemd services, **Docker** (containers, images, Compose projects), **scheduled tasks** (cron, systemd timers), listening ports, and a **Firewall** tab: the server's firewall (ufw, nftables, iptables) and the OVHcloud one side by side for each public port, with ufw rules to copy — SSH open only to the sources you list, incoming IPv6 blocked if you want. |
| **Vulnerabilities** | CVEs of every package, from the Debian Security Tracker and Ubuntu's OSV data, matched with the inventory — no extra command on the servers; signed packages (grub, shim, kernel, fwupd) compared with the code they sign. Grouped **by package with the update to make**, in two tabs: the CVEs of the servers' packages, and those of their Docker images (fixed by updating the image), and **the commands to fix a CVE** (`apt-get install --only-upgrade …`, or `docker compose pull` and `up -d` for an image) — to copy, never run by Elio. Scores from NVD, Red Hat and CVE.org (or your own providers), exploitation from EPSS and CISA KEV. |
| **Docker** | A **Docker state** per server, apart from its health: critical for unhealthy or looping containers, to watch for vulnerable images or images to update — a pill next to the health badge, a filter of the fleet list, its own notifications. Images per server, **new versions published on the registries** (Docker Hub, GHCR, Quay, private ones), vulnerabilities of the images (Trivy or Grype if installed, else Elio's own matching) in the server's Docker tab and on the Docker page, by image, with the servers and containers that run it. |
| **SSH keys** | A shared keyring (people and machines), keys added to or removed from a server in one click, **temporary access** that expires on its own, **the keys of every account** of a server (with root), unknown keys flagged and gathered in an **Outside the keyring** list, rotation of Elio's own key without downtime. |
| **Alerts** | What needs attention, by severity, on the overview, each with what to do; a journal of events; notifications to Slack, Discord, email or a signed webhook, grouped by type (critical ones right away); daily digest. |
| **Automation** | Every collection runs on schedule, on the whole fleet or per group, followed live in the *Runs* tab of the *Journal*. |
| **Extensions** | **Uptime Kuma** (monitors attached to each server), **OVHcloud** (IPs, network firewall, DNS records, services), **Technitium DNS** (zones and records), **Gandi** (LiveDNS records, domains and their expiry) and **Coolify** (what it runs on each server, deployments, backups; one connection per team), read-only, with **one DNS of the fleet** and **prompts for an AI assistant** (monitors to create, firewall rules) that end with your own instructions. |
| **Team** | Roles (admin, operator, read-only), invitations, mandatory two-factor authentication, **notes on each server** (Markdown) in its journal, ⌘K search everywhere, light and dark themes, the same layout on every page (one Save per settings page, dangerous actions behind a menu and a confirmation). |

| | |
|:---:|:---:|
| ![Vulnerabilities grouped by package](docs/screenshots/en/vulnerabilities-by-package.png) | ![A CVE in detail](docs/screenshots/en/vulnerability-detail.png) |
| **Vulnerabilities by package**, with the update to make | **A CVE in detail**: scores per provider, CVSS vector in words |
| ![A server](docs/screenshots/en/server.png) | ![Docker](docs/screenshots/en/docker.png) |
| **A server**: health, 24-hour charts, system | **Docker**: containers, images, updates, CVEs |
| ![Overview](docs/screenshots/en/overview.png) | ![Dark theme](docs/screenshots/en/fleet-dark.png) |
| **What needs attention**, most serious first | **Dark theme** |
| ![SSH keys of every account](docs/screenshots/en/ssh-keys.png) | ![Notes](docs/screenshots/en/notes.png) |
| **SSH keys** of every account of a server | **Journal** of a server: the team's notes and its history |
| ![Uptime Kuma monitors](docs/screenshots/en/uptime-kuma-monitors.png) | ![OVHcloud](docs/screenshots/en/ovh.png) |
| **Probes**: the Uptime Kuma monitors attached to each server | **Hosting**: the OVHcloud service, IPs and reverse of a server |
| ![DNS of the fleet](docs/screenshots/en/dns.png) | ![CVEs of the Docker images](docs/screenshots/en/docker-cves.png) |
| **DNS of the fleet**: OVHcloud, Technitium and Gandi together | **CVEs of the Docker images**, by image |
| ![Firewall tab](docs/screenshots/en/firewall.png) | ![Firewall settings](docs/screenshots/en/firewall-settings.png) |
| **Firewall**: the server's and OVH's, port by port, IPv6 included | **Suggested rules**: SSH sources, incoming IPv6 |

The interface is in **English and French**. Each user picks a language in *My account*; otherwise Elio follows the browser, then the default language of the installation (*Settings → General*). Notification channels and invitations have their own language. Adding a language is adding a folder of translations: see [CONTRIBUTING.md](CONTRIBUTING.md#translating-elio).

## Quick start

With Docker:

```sh
mkdir elio && cd elio
curl -fsSLO https://raw.githubusercontent.com/elio-fleet/elio/main/docker-compose.yml
docker run --rm ghcr.io/elio-fleet/elio:beta bin/elio-keys > .env    # the secrets of your installation
echo "ELIO_DATABASE_PASSWORD=$(openssl rand -hex 24)" >> .env
docker compose up -d
```

Open <http://localhost:8080> and create the first account: it is the administrator. Then, in *Settings → General*, generate Elio's SSH key, add it to a server's `~/.ssh/authorized_keys`, and add the server.

**Keep `.env` safe**: without its keys, the encrypted data (Elio's SSH key, API keys, webhooks) cannot be read back.

## Installing for real

Elio is a Rails application with PostgreSQL. Put it behind a reverse proxy with HTTPS (Caddy, Traefik, nginx).

- **Docker Compose**: the [`docker-compose.yml`](docker-compose.yml) above. Behind your HTTPS proxy, set `ELIO_HOST` (your domain) and remove `ELIO_FORCE_SSL: "false"`.
- **Kamal**: [`config/deploy.yml`](config/deploy.yml) is ready (HTTPS with Let's Encrypt); put the secrets in `.kamal/secrets` and run `bin/kamal setup`.
- **Updates**: pull the new image (`docker compose pull && docker compose up -d`); migrations run on start.
- **Backups**: the PostgreSQL databases and the `storage` volume (known host keys of the servers).

### Configuration

| Variable | |
|---|---|
| `SECRET_KEY_BASE`, `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Secrets of the installation, printed by `bin/elio-keys`. **Required.** (An installation that keeps them in Rails credentials sets `RAILS_MASTER_KEY` instead.) |
| `ELIO_DATABASE_PASSWORD`, `PGHOST` | PostgreSQL password of the `elio` user, and host. Elio uses four databases: `elio_production`, `_cache`, `_queue`, `_cable`. |
| `ELIO_HOST` | Elio's domain: links in emails and notifications, and the only host name it answers to. |
| `ELIO_SETUP_TOKEN` | If set, asked when creating the first account (useful when Elio is reachable before you set it up). |
| `ELIO_FORCE_SSL` | `false` only to try Elio over plain HTTP. HTTPS is forced otherwise. |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_AUTHENTICATION`, `ELIO_MAIL_FROM` | Emails: invitations, password reset, notifications. Without `SMTP_ADDRESS`, invitation links are to be copied. |
| `ELIO_PARALLEL_LIMIT` | Servers collected at the same time (4). |
| `ELIO_ACTIVITY_RETENTION_DAYS` | How long the activity log is kept (365, `0` = forever). |
| `ELIO_DEBIAN_TRACKER_URL`, `ELIO_UBUNTU_OSV_URL`, `ELIO_NVD_FEED_URL`, `ELIO_EPSS_URL`, `ELIO_KEV_URL` | Mirrors of the vulnerability feeds, for a closed network (they can also be imported by hand). |

Everything else — thresholds, notifications, automations, score providers, Docker registries, [extensions](#extensions) — is set in the interface, by an administrator. Secrets entered there (API keys, tokens, webhooks) are encrypted in the database.

### Preparing the servers

1. In *Settings → General*, generate Elio's SSH key (Ed25519, kept encrypted).
2. Add its public key to `~/.ssh/authorized_keys` of the account Elio will use (the page gives the command).
3. Add the server (or import many from a CSV or your `~/.ssh/config`), then run an inventory.

Elio reads everything an unprivileged account can read. Some details need root — the process behind each port, the firewall, Docker, the users' crontabs, the SSH keys of the other accounts: log in as root, or give the account password-less `sudo`. Without it, those collections are marked *partial*, and only the keys of Elio's account are listed.

Supported: **Debian and Ubuntu** (others get health and system only), Docker, snap.

## What Elio runs on your servers

**Every command is in [`config/ssh_commands.yml`](config/ssh_commands.yml)**, sorted by role then by distribution. It is the only place they are written: the application reads them from there, and a test fails if a command is sent from anywhere else. Values are always shell-escaped.

| For | Commands (read-only) |
|---|---|
| System, network | `/etc/os-release`, `uname`, `hostname`, `systemd-detect-virt`, `/proc`, `timedatectl`, `ip -j addr`, `ip -j link` |
| Health | `/proc/loadavg`, `/proc/meminfo`, `df`, `/var/run/reboot-required`, `systemctl --failed` (and `show` of the failed units), `apt-get -s dist-upgrade` (simulation) |
| Packages | `dpkg-query -W`, `apt list --upgradable`, `snap list` |
| Services, scheduled tasks | `systemctl list-units`, `list-unit-files`, `show` of the timers, `/etc/crontab`, `/etc/cron.d`, `/var/spool/cron` |
| Docker | `docker inspect` (state, health, restarts — **never the environment variables**), `docker stats`, `docker image inspect`, `docker system df`, `trivy` / `grype` if installed, `docker cp` of `os-release` and the dpkg status |
| Ports | `ss -tulpn`, `/proc/<pid>/cgroup`, `ufw status verbose`, `nft list ruleset`, `iptables -S INPUT` |
| SSH keys | reading `~/.ssh/authorized_keys` (with root, of every account with a login shell — never through a link, nor a file the account does not own); **writing only** when you add a key (to Elio's account, or with root to another existing account: its `~/.ssh` is created if missing, never the account) or remove one |

Elio **never changes the firewall** nor installs anything: suggested ufw rules and update commands are for you to review and run.

### The Firewall tab

Each server has a **Firewall** tab: the rules of its own firewall (ufw, nftables or iptables, read as root), the OVHcloud network firewall of its OVH IPs and its anti-DDoS, and a table of its public ports with the verdict of each firewall side by side. The OVHcloud firewall filters **only IPv4**: on a server with a public IPv6 address, the ports listening in IPv6 are shown *not covered (IPv6)*, and a health reason can report them (*Settings → Firewall*).

The **suggested ufw rules** can open SSH only to the sources you list in *Settings → Firewall* (Elio's own address, Coolify, your office… — each group of servers can choose some of them; include Elio's address, or applying the rules cuts its access), and can **block all the incoming IPv6** (the ports are then allowed from IPv4 only). The firewall prompt for an AI ends with your own instructions (*Settings → General*), e.g. "for the SSH port, always put the rules last".

## Extensions

Elio can read what your other tools know and show it next to each server. Enable them in *Settings → Extensions* (administrators). They **only read**: Elio never creates, changes or deletes anything on these services, and a disabled extension leaves no trace in the interface. Every alert they raise is optional, with its own threshold.

### Uptime Kuma

- **Setup**: the address of your instance and an API key (*Uptime Kuma → Settings → API Keys*). *Test the connection* checks them before saving.
- Elio reads the `/metrics` page every 15 minutes (Uptime Kuma 1.x and 2.x) and **attaches each monitor to its server**: by the IP it watches (WireGuard addresses included), by host name (with DNS resolution as an option), or by the server's name in the monitor's name (`[SRV] web-prod-1`). An attachment can be corrected by hand and is kept.
- A **Probes** tab on each server (source, state, response time, uptime over 24 hours and 30 days, certificate) and a **Probes** page: monitors attached to no server, servers without any monitor.
- Optional alerts: server without a monitor (with groups to ignore), monitor down or back, certificate about to expire, uptime under a threshold, monitor in maintenance for too long.

### OVHcloud

- **Setup**: the API endpoint (EU, CA, US), an Application Key, an Application Secret and a Consumer Key **limited to GET requests**. *Rights to give to the API key* lists the exact rights for the products you check and opens OVH's token page already filled in. *Test the connection* reports missing rights, and **warns if the key could write** — make a new one then.
- Each product is a checkbox: IPs and reverse DNS, network firewall, anti-DDoS, DNS zones (all or some), dedicated servers, VPS, Public Cloud instances (all projects or some).
- A **Hosting** card on the overview of each server: the OVH service (offer, datacenter, expiration), its IPs and reverse; the network firewall rules, **whether they let each public port through** and the anti-DDoS are in the [Firewall tab](#the-firewall-tab). A **Hosting** page: services, IPs, resources attached to no server. Its DNS records go to the [DNS of the fleet](#dns-of-the-fleet).
- Optional alerts: service about to expire (automatic renewal taken into account), network firewall disabled (IPv4 blocks: OVHcloud has no network firewall for IPv6), reverse DNS that does not match, OVH service not followed by Elio.

The OVH client of Elio only knows the GET method: it cannot write, whatever the key allows.

### DNS of the fleet

The extensions that read DNS (OVHcloud with its DNS product, Technitium DNS, Gandi) feed **one DNS of the fleet**:
- every A, AAAA and CNAME record is attached to its server the same way, whatever its source: a manual attachment **by name** (valid for every source), the IP of an A / AAAA record, or a CNAME to a name of any source;
- one **DNS** tab on each server and one **DNS** page (filters by source, zone, *outside the fleet*, *not attached*, *differs by source*), with the source of each record;
- a name whose records differ between sources (a public IP at OVH, a private one in Technitium) is flagged *differs by source*;
- the **alerts** are set once, in *Settings → Extensions → DNS*: record pointing to an IP outside the fleet, server without a DNS name (only if no source has one; groups can be ignored), and optionally a name that differs between sources. Nothing is reported for the first records of a newly enabled source;
- the fleet search, ⌘K, the Uptime Kuma monitors and the prompts use these names.

### Technitium DNS

- **Setup**: the address of the web console (port 5380 or 53443) and the API token of a user that can only **view** the zones. Technitium also has **permissions per zone**: give that user's group *View* on each zone to read, or the token sees none. *Test the connection* gives the version and the zones readable, and warns if the token could change them.
- Every hour, Elio reads the **A, AAAA and CNAME** records of the zones (all, or those you list) and attaches each one to its server: by the IP of an A / AAAA record, and for a CNAME by the record or the host it points to. A name can be attached by hand, and the attachment is kept.
- Its records go to the [DNS of the fleet](#dns-of-the-fleet).
- The token travels in an `Authorization: Bearer` header (never in the URL). Tested with Technitium DNS Server 15.6.

### Gandi

- **Setup**: a **personal access token** created in the Gandi Admin (*Organizations → Personal access tokens*) with **only the rights to see the domains and their DNS records** (LiveDNS), and an expiry you will renew; optionally the ID of the organization that owns the domains (otherwise Gandi lists only those of your personal organization). *Test the connection* gives the domains readable and those on LiveDNS.
- Every hour, Elio reads the **A, AAAA and CNAME** records of the domains served by LiveDNS (all, or those you list) and sends them to the [DNS of the fleet](#dns-of-the-fleet); the settings page lists your domains with their expiry date and auto renewal, and an optional alert reports a domain about to expire.
- Elio only sends `GET` requests to `https://api.gandi.net/v5/`, the token in an `Authorization: Bearer` header.

### Coolify

- **Setup**: one **connection per Coolify team** — a Coolify API token only sees its own team, and the API cannot list the others. For each team: in Coolify, *Settings → Advanced* turns *API access* on (add Elio's address to *Allowed API IPs* if it is filled in); switch to the team, then *Keys & Tokens → API Tokens*, a token with the **`read`** permission only. In Elio, *Settings → Extensions → Coolify → Add a connection*: the instance address and the token. Connections of one instance are grouped; several instances are fine. *Test the connection* gives the team, the version and the servers, and **warns if the token can read secrets** (`read:sensitive` or `root`) — make a `read` one then.
- Every 15 minutes, Elio reads each connection: the **servers** (attached to the servers of the fleet by address, host name or name; the server hosting Coolify by the instance's host name), every **application, service and database** with its project, environment, domains, deployed version and state, the **last deployments**, the **backup schedules** of the databases with their last runs, and the team's **SSH keys** (public part only).
- A **Coolify** tab on each server Coolify manages (resources, recent deployments, backups; each application links to its page in Coolify) and a **Coolify** page for the whole fleet. In the **Docker tab**, a container created by Coolify shows the name of its resource instead of its generated name; a port it publishes shows its resource on the Firewall tab, the Ports page and the prompts. Deployments go to the **server's journal** as they end. Coolify's SSH key is named in the keys tab instead of *outside the keyring*. The monitors prompt lists the domains Coolify serves, with their health check and existing monitor.
- Optional alerts: database backup failed or late (26 hours by default), database without a scheduled backup, failed last deployment, resource stopped (unless for more than 30 days) or unhealthy, server Coolify can no longer reach or use, database made public, domain served by Coolify whose DNS points elsewhere or has no record (with a DNS extension), Coolify's key on a server it does not manage, and application without a health check (off by default).
- Elio only sends `GET` requests to `<instance>/api/v1/`, the token in an `Authorization: Bearer` header. It never reads environment variables, Compose files or backup logs (a `read` token gets them redacted anyway). Tried on a real Coolify 4.6.0 instance with two teams.

## Security

- Elio's SSH key, API keys, webhooks and 2FA secrets are **encrypted in the database** and never sent back to the browser.
- Two-factor authentication (TOTP and backup codes), mandatory by default for administrators and operators; roles; invitations only (no public sign-up); rate-limited sign-in and lockout; strict Content Security Policy.
- Servers' host keys are pinned on first connection; a change blocks the connection until an administrator accepts it.
- **Outbound connections** of Elio: the vulnerability feeds and score providers (Debian, OSV, NVD, Red Hat, CVE.org, FIRST, CISA — only the releases and CVEs of your fleet), the Docker registries (manifest `HEAD` requests), and the extensions you enable (your Uptime Kuma instance, the OVH API, your Technitium DNS Server, the Gandi API, your Coolify instances — read-only, see [Extensions](#extensions)). Nothing else, no telemetry. In a closed network, the feeds can be imported by hand.
- The Docker image is built on Debian 13 and takes the Debian security updates at every build; the CVEs Elio may list in its own container are those Debian has not fixed yet (see [SECURITY.md](SECURITY.md#the-docker-image)).
- Found a vulnerability? Please report it privately: see [SECURITY.md](SECURITY.md).

## Known limits

- Full inventory for **Debian and Ubuntu** only. Ubuntu has not been tried on a real server yet.
- The Uptime Kuma, OVHcloud and Gandi extensions were built on recorded or documented API answers, not tried on a real account yet (Technitium DNS and Coolify were tried on real instances). Coolify: the databases inside a service (n8n's PostgreSQL…) are not followed yet, and the names of Coolify containers come from Coolify's source code.
- Container image CVEs without Trivy or Grype: Debian and Ubuntu based images only (not Alpine). Trivy and Grype have not been tried on a real server yet.
- Signed EFI packages (grub, shim, fwupd) were checked against real repository data, not on a real EFI server yet.
- Debian rates few of its CVEs: the scores come from the providers you enable (NVD, Red Hat, CVE.org by default).

## Development

```sh
bin/setup                 # gems, database, then the app on http://localhost:3000
bin/rails test            # tests
bin/ci                    # what the CI runs: style, security audits, tests, system tests
```

Ruby (see `.ruby-version`), PostgreSQL, Chrome for the system tests. See [CONTRIBUTING.md](CONTRIBUTING.md) for the conventions and the code layout.

Built with Ruby on Rails 8, Hotwire, Tailwind CSS, Solid Queue and [net-ssh](https://github.com/net-ssh/net-ssh).

## License

[AGPL-3.0](LICENSE). You can use, modify and host Elio; if you offer it as a service to others, share your changes.
