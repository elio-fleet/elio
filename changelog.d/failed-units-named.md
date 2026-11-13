### Changed

- **Failed services named**: the health reason names the failed units ("nginx, mnt-backup.mount and php-fpm failed", then "and 2 others" beyond three) instead of "3 services failed", on the server page, the dashboard and in the notifications.
- **Services tab**: each failed unit says since when it failed, and the failed units that are not services (mounts, sockets…) or that failed after the last services inventory are listed too (seen by the health reading, which runs more often). The tab's count includes them.
