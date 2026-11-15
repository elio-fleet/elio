### Added

- **Mattermost and Rocket.Chat notifications**: a new "Slack-compatible" channel takes the address of an incoming webhook of these services (any HTTPS address) and sends the Slack message format, mentions included.
- **Webhooks on the internal network over plain HTTP**: a generic or Slack-compatible channel may use an `http://` address when the administrator ticks "Allow a plain HTTP address" on it (off by default; Slack and Discord stay HTTPS only).

### Upgrading

- One migration (`notification_channels.allow_http`), run on start as usual.
