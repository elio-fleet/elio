# The wording of an extension's connections: generic ("Connections", "Add a
# connection") unless the extension words them its own way under
# integrations.<kind>.wording (manual DNS: "Sources", "Add a source").
module IntegrationWordingHelper
  def integration_text(kind, key, **options)
    t("integrations.#{kind}.wording.#{key}", **options, default: t(key, **options))
  end
end
