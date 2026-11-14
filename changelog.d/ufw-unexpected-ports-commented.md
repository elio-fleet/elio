### Changed

- **Suggested ufw rules**: without expected ports for the server's groups, every port listening publicly got an "allow" rule, so copying the rules opened a database or an exporter to the whole Internet. Now only SSH, 80 and 443 are allowed; the other public ports are written as commented lines with the reason, and a line at the top invites you to list the expected ports of the group.
