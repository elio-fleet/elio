# Debian marks some open issues it will not fix through a security advisory
# ("no-dsa": minor, "postponed": in a later update, "ignored": not at all);
# kept on the feed entries and on the CVEs of the servers so they are shown
# apart from those still waiting for a fix. The Debian feed is downloaded
# again in full (its validators dropped): an unchanged file would otherwise
# keep its entries without the status.
class AddDistroStatusToVulnerabilities < ActiveRecord::Migration[8.1]
  def change
    add_column :vulnerabilities, :distro_status, :string
    add_column :server_vulnerabilities, :distro_status, :string

    reversible do |direction|
      direction.up { execute "UPDATE vulnerability_feeds SET download_validators = '{}' WHERE source = 'debian'" }
    end
  end
end
