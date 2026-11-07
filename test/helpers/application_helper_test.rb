require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # Normally provided by the Authorization concern.
  def can?(permission) = (@user || users(:one)).can?(permission)
  test "relative_time_in_words in French, past and future" do
    freeze_time do
      assert_equal "à l'instant", relative_time_in_words(30.seconds.ago)
      assert_equal "dans moins d'une minute", relative_time_in_words(30.seconds.from_now)
      assert_equal "il y a 1 minute", relative_time_in_words(1.minute.ago)
      assert_equal "il y a 3 minutes", relative_time_in_words(3.minutes.ago)
      assert_equal "dans 10 minutes", relative_time_in_words(9.minutes.from_now + 30.seconds)
      assert_equal "dans 1 heure", relative_time_in_words(60.minutes.from_now)
      assert_equal "il y a 4 heures", relative_time_in_words(4.hours.ago)
      assert_equal "dans 1 jour", relative_time_in_words(1.day.from_now)
      assert_equal "il y a 7 jours", relative_time_in_words(7.days.ago)
    end
  end

  test "relative_time_tag renders a live <time> with the exact date as tooltip" do
    freeze_time do
      time = 9.minutes.from_now
      render html: relative_time_tag(time, prefix: "Expire ", expired: "Expiré", class: "badge")

      assert_select "time.badge[datetime=?][title=?][data-controller=relative-time]", time.iso8601, I18n.l(time, format: :long), text: "Expire dans 9 minutes" do |element|
        assert_equal "Expire ", element.attr("data-relative-time-prefix-value").to_s
        assert_equal "Expiré", element.attr("data-relative-time-expired-value").to_s
      end
    end
  end

  test "relative_time_tag shows the expired text once the time has passed" do
    render html: relative_time_tag(1.minute.ago, prefix: "Expire ", expired: "Expiré")
    assert_select "time", text: "Expiré"
  end

  test "relative_time_tag without expired text keeps showing the relative time" do
    render html: relative_time_tag(3.minutes.ago)
    assert_select "time:not([data-relative-time-expired-value])", text: "il y a 3 minutes"
  end

  test "command_palette_items lists pages, servers and public_keys" do
    items = command_palette_items

    assert_equal [ "Pages", "Groupes", "Serveurs", "Clés SSH" ], items.map { |item| item[:group] }.uniq
    assert_includes items, { group: "Pages", label: "Serveurs", hint: "serveurs", url: servers_path }
    assert_includes items, { group: "Groupes", label: "Production", hint: "serveurs du groupe", url: servers_path(group: server_groups(:production).id) }
    assert_includes items, { group: "Serveurs", label: "Web", hint: "deploy@192.168.1.10 · Production", url: server_path(servers(:web)), keywords: "192.168.1.10", server: true }
    assert_includes items, { group: "Serveurs", label: "Backup", hint: "root@10.0.0.5", url: server_path(servers(:backup)), keywords: "10.0.0.5", server: true }
    assert_includes items, { group: "Clés SSH", label: "Alice", hint: "Personne", url: public_key_path(public_keys(:alice)) }
    assert_includes items, { group: "Clés SSH", label: "CI", hint: "Serveur", url: public_key_path(public_keys(:ci)) }
    assert(items.select { |item| item[:group] == "Serveurs" }.all? { |item| item[:server] }, "the browser builds their tabs")
  end

  test "command_palette_items finds a server by host name and every address" do
    servers(:db).update!(extra_addresses_text: "203.0.113.9")
    servers(:db).inventory_snapshots.create!(category: "os", status: "ok", data: { "hostname" => "pg-main.example.internal" }, collected_at: Time.current, checked_at: Time.current)
    servers(:db).update_columns(ip_addresses: [ "10.8.0.12" ])

    item = command_palette_items.find { |candidate| candidate[:label] == "Database" }
    assert_equal "admin@db.example.com · pg-main.example.internal · Production", item[:hint]
    assert_equal "pg-main.example.internal 10.8.0.12 203.0.113.9", item[:keywords]
  end

  test "ssh_key_install_command appends the public key with strict permissions" do
    assert_equal "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '#{ssh_keys(:main).public_key}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys",
                 ssh_key_install_command(ssh_keys(:main))
  end

  test "pluralize_fr treats 0 and 1 as singular" do
    assert_equal [ "0 ligne", "1 ligne", "2 lignes" ], [ 0, 1, 2 ].map { |count| pluralize_fr(count, "ligne", "lignes") }
  end


  test "suggested_public_key_name drops the host part of the comment" do
    assert_equal "alice", suggested_public_key_name(AuthorizedKey.new(type: "ssh-ed25519", key: "AAAA", comment: "alice@laptop"))
    assert_equal "Deploy key", suggested_public_key_name(AuthorizedKey.new(type: "ssh-ed25519", key: "AAAA", comment: "Deploy key"))
    assert_nil suggested_public_key_name(AuthorizedKey.new(type: "ssh-ed25519", key: "AAAA"))
    assert_nil suggested_public_key_name(AuthorizedKey.new(type: "ssh-ed25519", key: "AAAA", comment: "@host"))
  end

  test "command_palette_items hides the pages the role cannot use" do
    @user = users(:viewer)
    labels = command_palette_items.map { |item| item[:label] }

    assert_includes labels, "Serveurs"
    assert_includes labels, "Web"
    assert_includes labels, "Exécutions"
    assert_not_includes labels, "Suivi technique des jobs"
    assert_not_includes labels, "Ajouter un serveur"
    assert_not_includes labels, "Paramètres"

    @user = users(:operator)
    labels = command_palette_items.map { |item| item[:label] }
    assert_includes labels, "Ajouter un serveur"
    assert_not_includes labels, "Automatisations"

    @user = users(:one)
    assert_includes command_palette_items.map { |item| item[:label] }, "Suivi technique des jobs"
  end
end
