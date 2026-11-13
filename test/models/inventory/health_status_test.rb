require "test_helper"

class Inventory::HealthStatusTest < ActiveSupport::TestCase
  setup do
    @server = servers(:web)
    @server.update_columns(ssh_ok: true)
  end

  def health(name = :debian12, **overrides)
    data = Inventory::Collectors::Health.parse(file_fixture("inventory/health/#{name}.txt").read).merge(overrides.stringify_keys)
    @server.inventory_snapshots.create!(category: "health", status: "ok", data: data, collected_at: Time.current, checked_at: Time.current)
  end

  def os(id, version, name)
    @server.inventory_snapshots.create!(category: "os", status: "ok", data: { "id" => id, "version_id" => version, "name" => name },
                                        collected_at: Time.current, checked_at: Time.current)
  end

  def evaluate = Inventory::HealthStatus.evaluate(@server.reload)

  test "unknown before any health collection" do
    assert_equal Inventory::HealthStatus::Result.new(state: "unknown", reasons: []), evaluate
  end

  test "critical disk first, then the warnings" do
    health

    result = evaluate

    assert_equal "crit", result.state
    assert_equal [ [ "crit", "Disque / à 94\u00A0%" ], [ "warn", "fail2ban en échec" ] ], result.reasons.map { |reason| [ reason.tone, reason.text ] }
  end

  test "warnings: full inodes, reboot, clock, several failed services, high load" do
    health(:ubuntu2404, disks: [ { "mount" => "/", "used_percent" => 50, "inodes_used_percent" => 85 } ],
                        failed_units: %w[a.service b.service], load: [ 9.25, 1, 1 ])

    result = evaluate

    assert_equal "warn", result.state
    assert_equal [ "Inodes / à 85\u00A0%", "Charge 9,3 pour 4 processeurs", "Redémarrage requis", "a et b en échec", "Horloge non synchronisée" ],
                 result.reasons.map(&:text)
  end

  test "failed units by name, the others counted beyond three, in the reader's language" do
    health(:minimal, failed_units: %w[nginx.service mnt-backup.mount php8.3-fpm.service])
    reason = evaluate.reasons.sole
    assert_equal "nginx, mnt-backup.mount et php8.3-fpm en échec", reason.text
    assert_equal "nginx, mnt-backup.mount, and php8.3-fpm failed", I18n.with_locale(:en) { Inventory::HealthStatus.text(reason.to_h.deep_stringify_keys) }

    servers(:web).inventory_snapshots.where(category: "health").delete_all
    health(:minimal, failed_units: %w[a.service b.socket c.service d.service e.service])
    assert_equal [ "a, b.socket et 3 autres en échec" ], evaluate.reasons.map(&:text)
  end

  test "ok when every value is below the thresholds" do
    health(:minimal)
    assert_equal [ "ok", [] ], evaluate.to_h.values_at(:state, :reasons)
  end

  test "thresholds come from the settings" do
    health(:minimal, memory: { "used_percent" => 85 })
    assert_equal "ok", evaluate.state

    AppSetting.current.update!(health_memory_warn: 80)
    assert_equal [ "Mémoire à 85\u00A0%" ], evaluate.reasons.map(&:text)
  end

  test "a system past its end of support needs attention" do
    health(:minimal)
    os("debian", "10", "Debian GNU/Linux 10 (buster)")

    assert_equal [ "warn", [ "Debian GNU/Linux 10 (buster) n'est plus supporté" ] ], [ evaluate.state, evaluate.reasons.map(&:text) ]
  end

  test "a refused Elio key is critical" do
    @server.update_columns(ssh_ok: false)

    assert_equal [ "crit", [ "Clé Elio refusée : inventaire impossible" ] ], [ evaluate.state, evaluate.reasons.map(&:text) ]
  end

  test "a reason is stored as a key and written in the reader's language" do
    reason = Inventory::HealthStatus.reason("warn", :disk, percent: 83, mount: "/var").to_h
    assert_equal({ "tone" => "warn", "key" => "health.disk", "params" => { "percent" => 83, "mount" => "/var" } }, reason)

    assert_equal "Disque /var à 83\u00A0%", Inventory::HealthStatus.text(reason)
    assert_equal "Disk /var at 83%", I18n.with_locale(:en) { Inventory::HealthStatus.text(reason) }
    load = Inventory::HealthStatus.reason("warn", :load, load: 8.5, count: 4).to_h
    assert_equal "Charge 8,5 pour 4 processeurs", Inventory::HealthStatus.text(load)
    assert_equal "Load 8.5 for 4 processors", I18n.with_locale(:en) { Inventory::HealthStatus.text(load) }
  end

  test "a reason stored before the translations is still read" do
    assert_equal "Redémarrage requis", Inventory::HealthStatus.text({ "tone" => "warn", "text" => "Redémarrage requis" })
  end
end
