require "test_helper"

class Integrations::CoolifyBackupsTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers

  PG = "/databases/dbpg000000000000000000004/backups".freeze

  setup do
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    @integration = enable_coolify
    @connection = @integration.connections.first
  end

  # The pg-facturation schedule with these executions ([status, hours ago]).
  def backups(*executions, enabled: true, created: 30.days.ago)
    [ { "uuid" => "bkp1", "enabled" => enabled, "frequency" => "0 3 * * *", "save_s3" => true, "created_at" => created.iso8601, "message" => "secret dump output",
        "executions" => executions.each_with_index.map { |(status, hours), index| { "uuid" => "exe#{index}", "status" => status, "size" => 10, "message" => "password=x", "finished_at" => hours.hours.ago.iso8601 } } } ]
  end

  def sync(answer)
    fake_coolify("team_tools" => { PG => answer })
    @connection.reload.sync!
    CoolifyResource.find_by!(kind: "database", name: "pg-facturation")
  end

  def reasons = Integrations::Coolify.health_reasons(@integration.reload, servers(:web).reload).map(&:text).grep(/Sauvegarde|sauvegarde/)

  test "the schedules and their last executions are kept, never their messages" do
    fake_coolify
    @connection.sync!
    database = CoolifyResource.find_by!(name: "pg-facturation")
    assert_equal [ { "uuid" => "bkp00000000000000000001", "enabled" => true, "frequency" => "0 3 * * *", "s3" => true, "created_at" => "2026-01-10T10:00:00.000000Z",
                     "executions" => [ { "uuid" => "exe0000000000000000000003", "status" => "success", "size" => 1_288_490_188, "at" => "2026-11-07T03:00:12.000000Z" },
                                       { "uuid" => "exe0000000000000000000002", "status" => "failed", "size" => 0, "at" => "2026-11-06T03:00:04.000000Z" },
                                       { "uuid" => "exe0000000000000000000001", "status" => "success", "size" => 1_280_000_000, "at" => "2026-11-05T03:00:11.000000Z" } ] } ],
                 database.data["backups"]
    assert_not_includes sync(backups([ "failed", 1 ])).data.to_s, "password"
  end

  test "backup state: ok, failed, late, none; a running one is skipped, a new schedule is not late yet" do
    assert_equal :ok, sync(backups([ "success", 2 ], [ "failed", 26 ])).backup_state(26)
    assert_equal :failed, sync(backups([ "failed", 2 ], [ "success", 26 ])).backup_state(26)
    assert_equal :failed, sync(backups([ "running", 0 ], [ "failed", 24 ])).backup_state(26)
    assert_equal :late, sync(backups([ "success", 30 ])).backup_state(26)
    assert_equal :late, sync(backups).backup_state(26), "a schedule that never succeeded in 30 days"
    assert_equal :ok, sync(backups(created: 2.hours.ago)).backup_state(26)
    assert_equal :none, sync([]).backup_state(26)
    assert_equal :none, sync(backups([ "success", 1 ], enabled: false)).backup_state(26)
    assert_nil CoolifyResource.find_by!(name: "api-facturation").backup_state(26)
  end

  test "health reasons of the server, as chosen in the settings" do
    sync(backups([ "failed", 3 ]))
    assert_includes reasons, "Sauvegarde Coolify de pg-facturation en échec"
    sync(backups([ "success", 40 ]))
    assert_includes reasons, "Sauvegarde Coolify de pg-facturation : aucune réussie depuis 26 heures"
    @integration.update!(settings: { "backup_max_age_hours" => 48 })
    assert_empty reasons
    sync([])
    assert_includes reasons, "Base Coolify pg-facturation sans sauvegarde planifiée"
    @integration.update!(settings: { "alert_no_backup" => false })
    assert_empty reasons
  end

  test "the sync refreshes the health of the server, the attention list links to the Coolify tab" do
    sync(backups([ "failed", 3 ]))
    reason = servers(:web).reload.health_reasons.find { |candidate| candidate["key"] == "integrations.coolify.health.backup_failed" }
    assert_equal "crit", reason["tone"]
    assert_equal [ "Voir Coolify", "/servers/#{servers(:web).id}?tab=coolify" ], AttentionList.action_for(servers(:web), reason)
  end

  test "a new failed execution is logged once, never on the first sync" do
    sync(backups([ "failed", 30 ]))
    assert_equal 0, Activity.of_kind(:coolify_backup_failed).count, "first sync: history"
    sync(backups([ "failed", 30 ]))
    assert_equal 0, Activity.of_kind(:coolify_backup_failed).count, "nothing new"
    answer = backups([ "failed", 30 ])
    answer.first["executions"].unshift({ "uuid" => "exe-new", "status" => "failed", "finished_at" => 1.hour.ago.iso8601 })
    sync(answer)
    assert_equal [ "Sauvegarde Coolify de pg-facturation en échec (équipe Outils internes)" ], Activity.of_kind(:coolify_backup_failed).map(&:summary)
    assert_equal servers(:web), Activity.of_kind(:coolify_backup_failed).first.server
  end
end
