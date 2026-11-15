ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Never read or write the project's pinned host keys.
    Ssh::KnownHosts.file = Rails.root.join("tmp", "test", "known_hosts")
    parallelize_setup { |worker| Ssh::KnownHosts.file = Rails.root.join("tmp", "test", "known_hosts-#{worker}") }

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rate limits (public pages, scores asked on demand) are kept in memory across tests: start fresh.
    setup do
      Throttled::STORE.clear
      Vulnerabilities::Scores::OnDemand::STORE.clear
      ApplicationController.setup_done = false # some tests delete every user
    end

    # Add more helper methods to be used by all tests here...
  end
end
