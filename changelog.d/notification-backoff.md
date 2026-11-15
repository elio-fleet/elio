### Added

- **Signed webhook**: the channel card shows how to check a message (a short Python example next to the signing secret).

### Changed

- **A failing notification channel backs off**: instead of every notification retrying on its own (dozens of attempts in a few minutes), the channel waits 1, 2, 4… minutes, an hour at most, between attempts; what it could not send waits and leaves as one grouped message once it works again. The card shows the next attempt.
- **A channel failing for a day is turned off**, and a new activity, “Notification channel turned off”, tells the other channels. Turning it back on or changing its destination tries again right away.
- Notifications have their own job queue and pass before the jobs already waiting, such as the inventories of a whole fleet.
