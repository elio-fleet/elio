<!-- Title: a Conventional Commit, e.g. "feat(firewall): a Firewall tab on the server page". -->

## Why

<!-- For someone who does not code, in 3 lines at most: what this changes for the user, and why. Link the issue if any: Closes #123 -->

## Technical choices

<!-- For developers: how it works, what was chosen and why, what was tried and dropped, the limits. -->

## Screenshots

<!-- If the interface changes: before | after of each page touched. Otherwise "Not applicable". -->

| Before | After |
|---|---|
|  |  |

## Tests

<!-- What is tested, how; what could not be tested (and why). -->

## Checklist

- [ ] Tests added or updated, `bin/ci` green
- [ ] A fragment in [`changelog.d/`](../blob/develop/changelog.d/README.md), not `CHANGELOG.md`
- [ ] Texts in English **and** French (`config/locales/en|fr`)
- [ ] New commands on the servers (if any) only in `config/ssh_commands.yml`, read-only
