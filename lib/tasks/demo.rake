namespace :dev do
  desc "Fill the development database with the fictitious fleet of the screenshots (refuses a database that has servers, unless FORCE=1)"
  task demo: :environment do
    abort "dev:demo only runs in development (RAILS_ENV=#{Rails.env})." unless Rails.env.development?
    if Server.exists? && ENV["FORCE"] != "1"
      abort "This database already has #{Server.count} servers: dev:demo would mix them with the demo. FORCE=1 deletes every server (and what belongs to them) first."
    end
    require Rails.root.join("lib/elio/demo_fleet")

    ActiveRecord::Base.transaction do
      Server.destroy_all if ENV["FORCE"] == "1"
      admin = User.find_by(email: "demo@example.test") || User.create!(email: "demo@example.test", password: "password1234", role: "admin")
      operator = User.find_by(email: "operator@example.test") || User.create!(email: "operator@example.test", password: "password1234", role: "operator")
      AppSetting.current.update!(require_admin_two_factor: false, require_operator_two_factor: false)
      SshKey.generate!(comment: "elio-demo") unless SshKey.current

      fleet = Elio::DemoFleet.new
      built = fleet.build_core
      fleet.build_extensions_offline(built[:web], built[:db])
      fleet.build_dns_and_firewall(built[:db])
      fleet.build_notes(built[:db], admin: admin, operator: operator)
      Server.find_each(&:refresh_health!)
    end
    puts "Demo fleet ready: #{Server.count} servers. Sign in as demo@example.test / password1234 (2FA not required)."
  end
end
