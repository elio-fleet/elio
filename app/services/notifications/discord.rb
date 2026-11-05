# Sends messages to a Discord webhook, as an embed coloured by severity.
# Mentions are only allowed for @everyone when the channel asks for it, so
# text coming from servers cannot ping anyone.
class Notifications::Discord
  COLORS = { info: 0x2a78d6, warning: 0xfab219, critical: 0xd03b3b }.freeze

  def self.deliver(channel, activity)
    context = [ I18n.t("notifications.discord.by", author_name: activity.author_name), activity.server_name && I18n.t("notifications.discord.server", server_name: activity.server_name) ].compact.join(" · ")
    post(channel, embeds: [ { title: escape(activity.label).first(256), description: escape(activity.summary).first(4000),
                              color: COLORS.fetch(activity.severity), footer: { text: context.first(2048) },
                              timestamp: activity.created_at.iso8601 } ])
  end

  def self.deliver_test(channel)
    post(channel, embeds: [ { title: I18n.t("notifications.discord.test_title"), description: I18n.t("notifications.discord.test_text", escape: (escape(channel.name))), color: COLORS[:info] } ])
  end

  # Several activities of one kind (NotificationBatch::Group), as one embed.
  def self.deliver_batch(channel, group)
    embed = { title: escape(group.title).first(256), description: group.lines.map { |line| "• #{escape(line)}" }.join("\n").first(4000),
              color: COLORS.fetch(group.severity), timestamp: group.activities.last.created_at.iso8601, url: group.url }.compact
    post(channel, embeds: [ embed ])
  end

  def self.deliver_digest(channel, digest)
    post(channel, embeds: [ { title: escape(digest.title), description: digest.lines.map { |line| escape(line) }.join("\n").first(4000), color: COLORS[:info] } ])
  end

  def self.post(channel, payload)
    payload = payload.merge(content: ("@everyone" if channel.mention_channel), allowed_mentions: { parse: channel.mention_channel ? [ "everyone" ] : [] }).compact
    Notifications::Http.post(channel.webhook_url, payload.to_json, service: "Discord")
  end

  # Markdown and mentions of text coming from servers are neutralized.
  def self.escape(text)
    text.to_s.gsub(/([\\*_~`|>#\[\]()])/) { "\\#{$1}" }.gsub("@", "@​")
  end
end
