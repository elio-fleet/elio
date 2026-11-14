### Fixed

- **Trivy on real images**: its JSON report weighs 60 MB and more for common images (httpd, redis, python), above Elio's limit, so their vulnerabilities stayed unknown while the Docker inventory said "ok". Elio now asks Trivy for one line per CVE with only the fields it keeps (1.3 MB instead of 65 MB for `redis:7.0.11`), and a Docker inventory whose image scans failed is marked partial with the reason.

### Upgrading

- One command on the servers changes: `inventory.trivy_scan` uses `--format template` (still read-only, Trivy only writes its own cache).
