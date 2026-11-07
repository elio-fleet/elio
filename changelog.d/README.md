# Changelog fragments

Each pull request adds **one file** here instead of editing `CHANGELOG.md`
(they all edited the same `[Unreleased]` section and conflicted with each
other). Name it after the change: `changelog.d/firewall-tab.md`.

```markdown
### Added

- **Firewall tab** on the server page: …

### Upgrading

- What someone who updates must know (optional).
```

Headings: `Upgrading`, `Added`, `Changed`, `Fixed`, `Security`, `Removed`;
each entry is a `- ` line. At release time, `bin/changelog <version>` puts
every fragment into the version's section of `CHANGELOG.md` (`Upgrading`
becomes `Upgrading from <previous version>`) and deletes them.
`bin/changelog` alone shows what the next section would be.
