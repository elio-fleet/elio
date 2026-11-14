# The same account on the same machine (host, port, user) added twice gives
# two servers that are inventoried, scanned and alerted on twice: the model
# refuses it, this index makes sure of it. Host names are case-insensitive.
#
# An install may already hold such duplicates (nothing refused them before):
# the migration must not fail there, nor delete a server on its own. It then
# skips the index and names the duplicates; the model validation still
# refuses new ones, and `db:migrate:redo` adds the index once they are gone.
class AddUniqueAddressIndexToServers < ActiveRecord::Migration[8.1]
  INDEX = "index_servers_on_lower_host_port_username".freeze

  def up
    duplicates = select_rows(<<~SQL)
      SELECT lower(host), port, username, string_agg(name, ', ' ORDER BY id)
      FROM servers GROUP BY lower(host), port, username HAVING count(*) > 1
    SQL
    if duplicates.any?
      duplicates.each { |host, port, username, names| say "Duplicate servers for #{username}@#{host}:#{port}: #{names}", true }
      say "Unique index #{INDEX} not created: delete the duplicates above, then run `bin/rails db:migrate:redo:primary VERSION=20261115100000`.", true
      return
    end

    add_index :servers, "lower(host), port, username", unique: true, name: INDEX, if_not_exists: true
  end

  def down
    remove_index :servers, name: INDEX, if_exists: true
  end
end
