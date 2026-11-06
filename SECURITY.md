# Security policy

Elio holds the SSH key that opens your servers: security reports are taken seriously.

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately through GitHub:
[Security → Report a vulnerability](https://github.com/elio-fleet/elio/security/advisories/new)
(private security advisory). Include what you found, how to reproduce it and the version (`v0.1.0-beta.1`, a commit…).

You will get an answer within a week. Once a fix is released, the advisory is published with credit to you, unless you prefer otherwise.

## Supported versions

Elio is in beta: only the latest release (and `main`) receives security fixes.

## Scope

In scope: the Elio application (authentication, roles, 2FA, the handling of the SSH key and of the secrets, what it runs on the servers — see [`config/ssh_commands.yml`](config/ssh_commands.yml)), the extensions (the Uptime Kuma, OVHcloud, Technitium and Gandi clients, which must stay read-only, and the handling of their API keys), the Docker image and the release workflows.

Out of scope: vulnerabilities of the servers Elio monitors (that is what Elio reports to you), and attacks that need an administrator account of Elio or root on the machine running it.

## The Docker image

The image is built on the official `ruby:<version>-slim-trixie` image (Debian 13) and takes the Debian security updates at every build: the CI builds it every day and fails when a security update is still pending in it (`bin/image-security-updates`), and each release rebuilds it from fresh packages. Dependabot proposes the new base images.

If you monitor the server that runs Elio, Elio also lists the CVEs of its own image. Those that remain are the ones **Debian has not fixed yet** (no fixed version in the Debian Security Tracker); they disappear with the next release once Debian publishes a fix. Updating to the latest Elio release is the way to get the fixed packages.

