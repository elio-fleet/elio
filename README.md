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

> **Beta.** Elio is young (`v0.1.0-beta.3.1`). It is used on real servers, but expect rough edges, and read the [known limits](#known-limits).

## Features

| | |
|---|---|
| **Health** | Load, memory, swap, disks and inodes, reboot required, failed services, clock sync, pending updates — with thresholds you set and 30 days of history. |
| **Inventory** | System and end-of-support date, network addresses (WireGuard included), packages (dpkg, snap), systemd services, **Docker** (containers, images, Compose projects), **scheduled tasks** (cron, systemd timers), listening ports and firewall (ufw, nftables, iptables), with suggested ufw rules to copy. |
| **Vulnerabilities** | CVEs of every package, from the Debian Security Tracker and Ubuntu's OSV data, matched with the inventory — no extra command on the servers; signed packages (grub, shim, kernel, fwupd) compared with the code they sign. Grouped **by package with the update to make**, the server's own CVEs apart from those of its Docker images, and **the commands to fix a CVE** (`apt-get install --only-upgrade …`, or `docker compose pull` and `up -d` for an image) — to copy, never run by Elio. Scores from NVD, Red Hat and CVE.org (or your own providers), exploitation from EPSS and CISA KEV. |
| **Docker** | Unhealthy and restarting containers, images per server, **new versions published on the registries** (Docker Hub, GHCR, Quay, private ones), vulnerabilities of the images (Trivy or Grype if installed, else Elio's own matching) in a **CVE** tab: by image, with the servers and containers that run it. |
| **SSH keys** | A shared keyring (people and machines), keys added to or removed from a server in one click, **temporary access** that expires on its own, **the keys of every account** of a server (with root), unknown keys flagged and gathered in an **Outside the keyring** list, rotation of Elio's own key without downtime. |
| **Alerts** | What needs attention, by severity, on the overview; activity log; notifications to Slack, Discord, email or a signed webhook, grouped by type (critical ones right away); daily digest. |
| **Automation** | Every collection runs on schedule, on the whole fleet or per group, followed live in the *Tasks* page. |
| **Extensions** | **Uptime Kuma** (monitors attached to each server), **OVHcloud** (IPs, network firewall, DNS records, services) and **Technitium DNS** (zones and records), read-only, with **one DNS of the fleet** and **prompts for an AI assistant** (monitors to create, OVH firewall rules). |
| **Team** | Roles (admin, operator, read-only), invitations, mandatory two-factor authentication, **notes on each server** (Markdown), ⌘K search everywhere, light and dark themes. |

| | |
|:---:|:---:|
| ![Vulnerabilities grouped by package](docs/screenshots/en/vulnerabilities-by-package.png) | ![A CVE in detail](docs/screenshots/en/vulnerability-detail.png) |
| **Vulnerabilities by package**, with the update to make | **A CVE in detail**: scores per provider, CVSS vector in words |
| ![A server](docs/screenshots/en/server.png) | ![Docker](docs/screenshots/en/docker.png) |
| **A server**: health, 24-hour charts, system | **Docker**: containers, images, updates, CVEs |
| ![Overview](docs/screenshots/en/overview.png) | ![Dark theme](docs/screenshots/en/fleet-dark.png) |
| **What needs attention**, most serious first | **Dark theme** |
| ![SSH keys of every account](docs/screenshots/en/ssh-keys.png) | ![Notes](docs/screenshots/en/notes.png) |
| **SSH keys** of every account of a server | **Notes** of the team on a server |
| ![Uptime Kuma monitors](docs/screenshots/en/uptime-kuma-monitors.png) | ![OVHcloud](docs/screenshots/en/ovh.png) |
| **Uptime Kuma**: monitors attached to each server | **OVHcloud**: service, IPs, network firewall per port |
| ![DNS of the fleet](docs/screenshots/en/dns.png) | ![CVEs of the Docker images](docs/screenshots/en/docker-cves.png) |
| **DNS of the fleet**: OVHcloud and Technitium together | **CVEs of the Docker images**, by image |

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

Open <http://localhost:8080> and create the first account: it is the administrator. Then, in *Paramètres → Général*, generate Elio's SSH key, add it to a server's `~/.ssh/authorized_keys`, and add the server.

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

1. In *Paramètres → Général*, generate Elio's SSH key (Ed25519, kept encrypted).
2. Add its public key to `~/.ssh/authorized_keys` of the account Elio will use (the page gives the command).
3. Add the server (or import many from a CSV or your `~/.ssh/config`), then run an inventory.

Elio reads everything an unprivileged account can read. Some details need root — the process behind each port, the firewall, Docker, the users' crontabs, the SSH keys of the other accounts: log in as root, or give the account password-less `sudo`. Without it, those collections are marked *partial*, and only the keys of Elio's account are listed.

Supported: **Debian and Ubuntu** (others get health and system only), Docker, snap.

## What Elio runs on your servers

**Every command is in [`config/ssh_commands.yml`](config/ssh_commands.yml)**, sorted by role then by distribution. It is the only place they are written: the application reads them from there, and a test fails if a command is sent from anywhere else. Values are always shell-escaped.

| For | Commands (read-only) |
|---|---|
| System, network | `/etc/os-release`, `uname`, `hostname`, `systemd-detect-virt`, `/proc`, `timedatectl`, `ip -j addr`, `ip -j link` |
| Health | `/proc/loadavg`, `/proc/meminfo`, `df`, `/var/run/reboot-required`, `systemctl --failed`, `apt-get -s dist-upgrade` (simulation) |
| Packages | `dpkg-query -W`, `apt list --upgradable`, `snap list` |
| Services, scheduled tasks | `systemctl list-units`, `list-unit-files`, `show` of the timers, `/etc/crontab`, `/etc/cron.d`, `/var/spool/cron` |
| Docker | `docker inspect` (state, health, restarts — **never the environment variables**), `docker stats`, `docker image inspect`, `docker system df`, `trivy` / `grype` if installed, `docker cp` of `os-release` and the dpkg status |
| Ports | `ss -tulpn`, `/proc/<pid>/cgroup`, `ufw status verbose`, `nft list ruleset`, `iptables -S INPUT` |
| SSH keys | reading `~/.ssh/authorized_keys` (with root, of every account with a login shell — never through a link, nor a file the account does not own); **writing only** when you add a key (to Elio's account) or remove one |

Elio **never changes the firewall** nor installs anything: suggested ufw rules and update commands are for you to review and run.

## Extensions

Elio can read what your other tools know and show it next to each server. Enable them in *Paramètres → Extensions* (administrators). They **only read**: Elio never creates, changes or deletes anything on these services, and a disabled extension leaves no trace in the interface. Every alert they raise is optional, with its own threshold.

### Uptime Kuma

- **Setup**: the address of your instance and an API key (*Uptime Kuma → Settings → API Keys*). *Tester la connexion* checks them before saving.
- Elio reads the `/metrics` page every 15 minutes (Uptime Kuma 1.x and 2.x) and **attaches each monitor to its server**: by the IP it watches (WireGuard addresses included), by host name (with DNS resolution as an option), or by the server's name in the monitor's name (`[SRV] web-prod-1`). An attachment can be corrected by hand and is kept.
- A **Monitors** tab on each server (state, response time, uptime over 24 hours and 30 days, certificate) and a **Monitors** page: monitors attached to no server, servers without any monitor.
- Optional alerts: server without a monitor (with groups to ignore), monitor down or back, certificate about to expire, uptime under a threshold, monitor in maintenance for too long.

### OVHcloud

- **Setup**: the API endpoint (EU, CA, US), an Application Key, an Application Secret and a Consumer Key **limited to GET requests**. *Droits à donner à la clé API* lists the exact rights for the products you check and opens OVH's token page already filled in. *Tester la connexion* reports missing rights, and **warns if the key could write** — make a new one then.
- Each product is a checkbox: IPs and reverse DNS, network firewall, anti-DDoS, DNS zones (all or some), dedicated servers, VPS, Public Cloud instances (all projects or some).
- An **OVH** tab on each server: the OVH service (offer, datacenter, expiration), its IPs and reverse, the network firewall rules and **whether they let each public port through**, anti-DDoS. An **OVHcloud** page: services, IPs, resources attached to no server. Its DNS records go to the [DNS of the fleet](#dns-of-the-fleet).
- Optional alerts: service about to expire (automatic renewal taken into account), network firewall disabled, reverse DNS that does not match, OVH service not followed by Elio.

The OVH client of Elio only knows the GET method: it cannot write, whatever the key allows.

### DNS of the fleet

The extensions that read DNS (OVHcloud with its DNS product, Technitium DNS) feed **one DNS of the fleet**:
- every A, AAAA and CNAME record is attached to its server the same way, whatever its source: a manual attachment **by name** (valid for every source), the IP of an A / AAAA record, or a CNAME to a name of any source;
- one **DNS** tab on each server and one **DNS** page (filters by source, zone, *outside the fleet*, *not attached*, *differs by source*), with the source of each record;
- a name whose records differ between sources (a public IP at OVH, a private one in Technitium) is flagged *differs by source*;
- the **alerts** are set once, in *Settings → Extensions → DNS*: record pointing to an IP outside the fleet, server without a DNS name (only if no source has one; groups can be ignored), and optionally a name that differs between sources. Nothing is reported for the first records of a newly enabled source;
- the fleet search, ⌘K, the Uptime Kuma monitors and the prompts use these names.

### Technitium DNS

- **Setup**: the address of the web console (port 5380 or 53443) and the API token of a user that can only **view** the zones. Technitium also has **permissions per zone**: give that user's group *View* on each zone to read, or the token sees none. *Tester la connexion* gives the version and the zones readable, and warns if the token could change them.
- Every hour, Elio reads the **A, AAAA and CNAME** records of the zones (all, or those you list) and attaches each one to its server: by the IP of an A / AAAA record, and for a CNAME by the record or the host it points to. A name can be attached by hand, and the attachment is kept.
- Its records go to the [DNS of the fleet](#dns-of-the-fleet).
- The token travels in an `Authorization: Bearer` header (never in the URL). Tested with Technitium DNS Server 15.6.

## Security

- Elio's SSH key, API keys, webhooks and 2FA secrets are **encrypted in the database** and never sent back to the browser.
- Two-factor authentication (TOTP and backup codes), mandatory by default for administrators and operators; roles; invitations only (no public sign-up); rate-limited sign-in and lockout; strict Content Security Policy.
- Servers' host keys are pinned on first connection; a change blocks the connection until an administrator accepts it.
- **Outbound connections** of Elio: the vulnerability feeds and score providers (Debian, OSV, NVD, Red Hat, CVE.org, FIRST, CISA — only the releases and CVEs of your fleet), the Docker registries (manifest `HEAD` requests), and the extensions you enable (your Uptime Kuma instance, the OVH API, your Technitium DNS Server — read-only, see [Extensions](#extensions)). Nothing else, no telemetry. In a closed network, the feeds can be imported by hand.
- Found a vulnerability? Please report it privately: see [SECURITY.md](SECURITY.md).

## Known limits

- Full inventory for **Debian and Ubuntu** only. Ubuntu has not been tried on a real server yet.
- The Uptime Kuma and OVHcloud extensions were built on recorded API answers, not tried on a real account yet (Technitium DNS was tried on a real instance).
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
