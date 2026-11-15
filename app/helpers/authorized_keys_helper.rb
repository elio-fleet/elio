# The restrictions an authorized_keys line puts on its key (AuthorizedKey#option_list),
# in the server key list (server_authorized_keys/_account and _key_details).
module AuthorizedKeysHelper
  # Options with a sentence of their own in the details (`server_authorized_keys.options.labels`).
  KNOWN_KEY_OPTIONS = %w[
    from command expiry-time restrict no-pty no-port-forwarding no-agent-forwarding no-x11-forwarding
    permitopen permitlisten principals environment cert-authority
  ].freeze

  KEY_OPTION_BADGE = "inline-flex max-w-56 items-center truncate rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset"

  # Badges for the options that change who may use the key and how: origin
  # (from=), forced command, restrict, expiry. `expiry`: false when the expiry
  # is already shown (a temporary access given through Elio).
  def key_option_badges(key, expiry: true)
    neutral = "#{KEY_OPTION_BADGE} bg-subtle text-ink-2 ring-line"
    badges = []
    if (from = key.option("from"))
      badges << tag.span(t("server_authorized_keys.options.from", from: from), class: "key-option key-option-from #{neutral}", title: from)
    end
    if (command = key.option("command"))
      badges << tag.span(t("server_authorized_keys.options.command"), class: "key-option key-option-command #{neutral}", title: command)
    end
    if key.option_list.any? { |name, _| name == "restrict" }
      badges << tag.span(t("server_authorized_keys.options.restrict"), class: "key-option key-option-restrict #{neutral}")
    end
    if expiry && key.expires_at
      badges << relative_time_tag(key.expires_at, prefix: t("public_keys.accesses.expires"), expired: t("server_authorized_keys.options.expired"),
                                                  class: "key-option key-option-expiry #{KEY_OPTION_BADGE} bg-warn-soft text-warn-ink ring-warn/20")
    end
    safe_join(badges)
  end

  # What an option does, in a few words; its own name for an unknown one.
  def key_option_label(name)
    KNOWN_KEY_OPTIONS.include?(name) ? t("server_authorized_keys.options.labels.#{name.tr("-", "_")}") : name
  end

  # The value of an option as shown in the details: the expiry as a date.
  def key_option_value(key, name, value)
    return value unless name == "expiry-time" && key.expires_at

    text = l(key.expires_at, format: :long)
    key.expiry_local_time? ? t("server_authorized_keys.options.server_local_time", time: text) : "#{text} UTC"
  end
end
