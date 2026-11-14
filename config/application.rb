require_relative "boot"

require "rails"
# The parts of Rails Elio uses (no Active Storage, Action Text, Action Mailbox).
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"
require_relative "../lib/elio/secrets"
require_relative "../lib/elio/version"
require_relative "../lib/elio/locales"
require_relative "../lib/elio/mail"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Elio
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets elio tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Europe/Paris"
    # The interface languages: one folder per language in config/locales
    # (Elio::Locales). Each user picks one, else the browser's, else the
    # instance's (Settings → General); English when nothing decides.
    config.i18n.available_locales = Elio::Locales.available
    config.i18n.default_locale = Elio::Locales::DEFAULT
    # config.eager_load_paths << Rails.root.join("extras")

    # Database encryption keys from the environment (lib/elio/secrets.rb),
    # else Rails credentials. SECRET_KEY_BASE is read by Rails itself.
    Elio::Secrets.encryption_keys.each { |key, value| config.active_record.encryption.public_send(:"#{key}=", value) }
  end
end
