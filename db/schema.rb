# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_05_225805) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_snapshots", force: :cascade do |t|
    t.bigint "server_id", null: false
    t.string "unix_user", null: false
    t.text "content", default: "", null: false
    t.datetime "read_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["server_id", "unix_user"], name: "index_account_snapshots_on_server_id_and_unix_user", unique: true
    t.index ["server_id"], name: "index_account_snapshots_on_server_id"
  end

  create_table "activities", force: :cascade do |t|
    t.string "kind", null: false
    t.bigint "user_id"
    t.bigint "server_id"
    t.bigint "public_key_id"
    t.string "unix_user"
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_activities_on_created_at"
    t.index ["kind"], name: "index_activities_on_kind"
    t.index ["public_key_id"], name: "index_activities_on_public_key_id"
    t.index ["server_id", "created_at"], name: "index_activities_on_server_id_and_created_at"
    t.index ["user_id"], name: "index_activities_on_user_id"
  end

  create_table "app_settings", force: :cascade do |t|
    t.boolean "require_admin_two_factor", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "health_disk_warn", default: 80, null: false
    t.integer "health_disk_crit", default: 90, null: false
    t.integer "health_memory_warn", default: 90, null: false
    t.integer "health_memory_crit", default: 95, null: false
    t.decimal "health_load_warn", precision: 4, scale: 1, default: "2.0", null: false
    t.boolean "require_operator_two_factor", default: true, null: false
    t.string "vulnerability_alert_severity", default: "high", null: false
    t.boolean "docker_alert_unhealthy", default: true, null: false
    t.boolean "docker_alert_restarts", default: true, null: false
    t.boolean "docker_alert_updates", default: false, null: false
    t.text "docker_registry_credentials"
    t.jsonb "score_bands", default: [{"from" => 0, "color" => "green"}, {"from" => 4, "color" => "orange"}, {"from" => 7, "color" => "red"}], null: false
    t.string "default_locale", default: "en", null: false
    t.boolean "dns_alert_outside", default: false, null: false
    t.boolean "dns_alert_without_name", default: false, null: false
    t.jsonb "dns_without_name_ignored_group_ids", default: [], null: false
    t.boolean "dns_alert_conflict", default: false, null: false
    t.jsonb "dns_alert_state", default: {}, null: false
  end

  create_table "automations", force: :cascade do |t|
    t.string "kind", null: false
    t.boolean "enabled", default: false, null: false
    t.integer "interval_minutes", null: false
    t.datetime "last_run_at"
    t.string "last_result"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state", default: {}, null: false
    t.jsonb "server_group_ids", default: [], null: false
    t.index ["kind"], name: "index_automations_on_kind", unique: true
  end

  create_table "background_task_items", force: :cascade do |t|
    t.bigint "background_task_id", null: false
    t.bigint "server_id"
    t.string "server_name", null: false
    t.string "status", default: "queued", null: false
    t.text "message"
    t.jsonb "details", default: {}, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "active_job_id"
    t.index ["background_task_id"], name: "index_background_task_items_on_background_task_id"
    t.index ["server_id"], name: "index_background_task_items_on_server_id"
  end

  create_table "background_tasks", force: :cascade do |t|
    t.string "kind", null: false
    t.string "label", null: false
    t.string "status", default: "queued", null: false
    t.bigint "user_id"
    t.bigint "automation_id"
    t.text "result"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "active_job_id"
    t.index ["automation_id"], name: "index_background_tasks_on_automation_id"
    t.index ["created_at"], name: "index_background_tasks_on_created_at"
    t.index ["status", "created_at"], name: "index_background_tasks_on_status_and_created_at"
    t.index ["user_id"], name: "index_background_tasks_on_user_id"
  end

  create_table "cve_ratings", force: :cascade do |t|
    t.string "cve", null: false
    t.decimal "score", precision: 3, scale: 1
    t.integer "scores_count", default: 0, null: false
    t.decimal "epss", precision: 6, scale: 5
    t.decimal "epss_percentile", precision: 6, scale: 5
    t.boolean "exploited", default: false, null: false
    t.date "exploited_since"
    t.datetime "updated_at", null: false
    t.index ["cve"], name: "index_cve_ratings_on_cve", unique: true
  end

  create_table "cve_scores", force: :cascade do |t|
    t.string "cve", null: false
    t.string "provider_key", null: false
    t.decimal "score", precision: 7, scale: 5
    t.string "version"
    t.string "vector"
    t.string "severity"
    t.jsonb "data", default: {}, null: false
    t.datetime "fetched_at", null: false
    t.index ["cve", "provider_key"], name: "index_cve_scores_on_cve_and_provider_key", unique: true
    t.index ["provider_key"], name: "index_cve_scores_on_provider_key"
  end

  create_table "dns_links", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "server_id"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_dns_links_on_name", unique: true
    t.index ["server_id"], name: "index_dns_links_on_server_id"
    t.index ["user_id"], name: "index_dns_links_on_user_id"
  end

  create_table "dns_records", force: :cascade do |t|
    t.string "source", null: false
    t.string "source_id", null: false
    t.string "zone", null: false
    t.string "name", null: false
    t.string "record_type", null: false
    t.string "value", null: false
    t.integer "ttl"
    t.boolean "disabled", default: false, null: false
    t.bigint "server_id"
    t.string "matched_by"
    t.string "matched_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_dns_records_on_name"
    t.index ["server_id"], name: "index_dns_records_on_server_id"
    t.index ["source", "source_id"], name: "index_dns_records_on_source_and_source_id", unique: true
  end

  create_table "image_updates", force: :cascade do |t|
    t.string "reference", null: false
    t.string "registry", null: false
    t.string "repository", null: false
    t.string "tag", null: false
    t.string "remote_digest"
    t.datetime "checked_at"
    t.string "error"
    t.index ["reference"], name: "index_image_updates_on_reference", unique: true
  end

  create_table "integration_links", force: :cascade do |t|
    t.bigint "integration_id", null: false
    t.string "external_id", null: false
    t.bigint "server_id"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["integration_id", "external_id"], name: "index_integration_links_on_integration_id_and_external_id", unique: true
    t.index ["integration_id"], name: "index_integration_links_on_integration_id"
    t.index ["server_id"], name: "index_integration_links_on_server_id"
    t.index ["user_id"], name: "index_integration_links_on_user_id"
  end

  create_table "integrations", force: :cascade do |t|
    t.string "kind", null: false
    t.boolean "enabled", default: false, null: false
    t.jsonb "settings", default: {}, null: false
    t.text "secrets"
    t.jsonb "state", default: {}, null: false
    t.datetime "last_synced_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_integrations_on_kind", unique: true
  end

  create_table "inventory_health_samples", force: :cascade do |t|
    t.bigint "server_id", null: false
    t.datetime "collected_at", null: false
    t.float "load_percent"
    t.float "memory_percent"
    t.float "disk_percent"
    t.index ["collected_at"], name: "index_inventory_health_samples_on_collected_at"
    t.index ["server_id", "collected_at"], name: "index_inventory_health_samples_on_server_id_and_collected_at"
  end

  create_table "inventory_packages", force: :cascade do |t|
    t.bigint "server_id", null: false
    t.string "manager", null: false
    t.string "name", null: false
    t.string "version"
    t.string "arch"
    t.string "available_version"
    t.boolean "security", default: false, null: false
    t.string "source_name"
    t.string "source_version"
    t.index ["name"], name: "index_inventory_packages_on_name"
    t.index ["server_id"], name: "index_inventory_packages_on_server_id"
  end

  create_table "inventory_snapshots", force: :cascade do |t|
    t.bigint "server_id", null: false
    t.string "category", null: false
    t.jsonb "data", default: {}, null: false
    t.string "status", null: false
    t.text "message"
    t.boolean "privileged", default: false, null: false
    t.datetime "collected_at"
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["server_id", "category"], name: "index_inventory_snapshots_on_server_id_and_category", unique: true
    t.index ["server_id"], name: "index_inventory_snapshots_on_server_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.string "email", null: false
    t.string "role", default: "viewer", null: false
    t.string "token", null: false
    t.bigint "invited_by_id", null: false
    t.bigint "user_id"
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale"
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
    t.index ["user_id"], name: "index_invitations_on_user_id"
  end

  create_table "key_rotation_steps", force: :cascade do |t|
    t.bigint "key_rotation_id", null: false
    t.bigint "server_id"
    t.string "server_name", null: false
    t.string "status", null: false
    t.string "phase"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_rotation_id"], name: "index_key_rotation_steps_on_key_rotation_id"
    t.index ["server_id"], name: "index_key_rotation_steps_on_server_id"
  end

  create_table "key_rotations", force: :cascade do |t|
    t.bigint "old_key_id"
    t.bigint "new_key_id"
    t.bigint "started_by_id"
    t.integer "servers_count", default: 0, null: false
    t.boolean "forced", default: false, null: false
    t.datetime "finished_at"
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["new_key_id"], name: "index_key_rotations_on_new_key_id"
    t.index ["old_key_id"], name: "index_key_rotations_on_old_key_id"
    t.index ["started_by_id"], name: "index_key_rotations_on_started_by_id"
  end

  create_table "notification_batches", force: :cascade do |t|
    t.bigint "notification_channel_id", null: false
    t.string "kind", null: false
    t.bigint "activity_ids", default: [], null: false, array: true
    t.datetime "send_at", null: false
    t.datetime "closed_at"
    t.datetime "delivered_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notification_channel_id", "kind"], name: "index_notification_batches_open", unique: true, where: "(closed_at IS NULL)"
    t.index ["send_at"], name: "index_notification_batches_undelivered", where: "((delivered_at IS NULL) AND (failed_at IS NULL))"
  end

  create_table "notification_channels", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", default: "slack", null: false
    t.text "webhook_url"
    t.jsonb "activity_kinds", default: [], null: false
    t.boolean "mention_channel", default: false, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_delivered_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "recipients"
    t.text "signing_secret"
    t.boolean "daily_digest", default: false, null: false
    t.datetime "last_digest_at"
    t.string "locale"
    t.integer "group_minutes", default: 10, null: false
    t.index ["name"], name: "index_notification_channels_on_name", unique: true
  end

  create_table "ovh_resources", force: :cascade do |t|
    t.string "kind", null: false
    t.string "external_id", null: false
    t.string "name", null: false
    t.jsonb "data", default: {}, null: false
    t.jsonb "addresses", default: [], null: false
    t.date "expires_at"
    t.bigint "server_id"
    t.string "matched_by"
    t.string "matched_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "external_id"], name: "index_ovh_resources_on_kind_and_external_id", unique: true
    t.index ["server_id"], name: "index_ovh_resources_on_server_id"
  end

  create_table "public_keys", force: :cascade do |t|
    t.string "name", null: false
    t.text "content", null: false
    t.string "fingerprint", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kind", default: "person", null: false
    t.text "description"
    t.index "lower((name)::text)", name: "index_public_keys_on_lower_name", unique: true
    t.index ["fingerprint"], name: "index_public_keys_on_fingerprint", unique: true
  end

  create_table "score_providers", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "position", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.jsonb "state", default: {}, null: false
    t.datetime "last_run_at"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_score_providers_on_key", unique: true
  end

  create_table "server_group_memberships", force: :cascade do |t|
    t.bigint "server_id", null: false
    t.bigint "server_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["server_group_id", "server_id"], name: "idx_on_server_group_id_server_id_9a8ddc3e88", unique: true
    t.index ["server_group_id"], name: "index_server_group_memberships_on_server_group_id"
    t.index ["server_id"], name: "index_server_group_memberships_on_server_id"
  end

  create_table "server_groups", force: :cascade do |t|
    t.string "name", null: false
    t.string "color", default: "slate", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "expected_ports"
    t.index "lower((name)::text)", name: "index_server_groups_on_lower_name", unique: true
  end

  create_table "server_notes", force: :cascade do |t|
    t.bigint "server_id", null: false
    t.bigint "user_id"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["server_id", "created_at"], name: "index_server_notes_on_server_id_and_created_at"
    t.index ["user_id"], name: "index_server_notes_on_user_id"
  end

  create_table "server_vulnerabilities", force: :cascade do |t|
    t.bigint "server_id", null: false
    t.string "origin", default: "host", null: false
    t.string "source", null: false
    t.string "image"
    t.string "cve", null: false
    t.string "source_package", null: false
    t.string "packages", default: [], null: false, array: true
    t.string "installed_version"
    t.string "fixed_version"
    t.string "severity", null: false
    t.string "description"
    t.string "distro_severity"
    t.index ["cve"], name: "index_server_vulnerabilities_on_cve"
    t.index ["server_id", "origin"], name: "index_server_vulnerabilities_on_server_id_and_origin"
    t.index ["server_id"], name: "index_server_vulnerabilities_on_server_id"
  end

  create_table "servers", force: :cascade do |t|
    t.string "name", null: false
    t.string "host", null: false
    t.integer "port", default: 22, null: false
    t.string "username", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "reachable"
    t.datetime "last_checked_at"
    t.boolean "ssh_ok"
    t.datetime "ssh_checked_at"
    t.string "privilege"
    t.datetime "inventoried_at"
    t.string "os_name"
    t.string "os_id"
    t.string "os_version"
    t.string "health_status"
    t.jsonb "health_reasons", default: [], null: false
    t.jsonb "ip_addresses", default: [], null: false
    t.jsonb "extra_addresses", default: [], null: false
    t.datetime "vulnerabilities_checked_at"
    t.index "lower((name)::text)", name: "index_servers_on_lower_name", unique: true
    t.index ["ip_addresses"], name: "index_servers_on_ip_addresses", using: :gin
  end

  create_table "ssh_keys", force: :cascade do |t|
    t.text "public_key", null: false
    t.text "private_key", null: false
    t.string "fingerprint", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "state", default: "active", null: false
  end

  create_table "temporary_accesses", force: :cascade do |t|
    t.bigint "server_id", null: false
    t.bigint "public_key_id"
    t.string "unix_user", null: false
    t.text "key_blob", null: false
    t.string "fingerprint", null: false
    t.datetime "expires_at", null: false
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_temporary_accesses_active_expiry", where: "(ended_at IS NULL)"
    t.index ["public_key_id"], name: "index_temporary_accesses_on_public_key_id"
    t.index ["server_id", "unix_user", "fingerprint"], name: "index_temporary_accesses_active_key", unique: true, where: "(ended_at IS NULL)"
    t.index ["server_id"], name: "index_temporary_accesses_on_server_id"
  end

  create_table "uptime_kuma_monitors", force: :cascade do |t|
    t.string "monitor_id", null: false
    t.string "name", null: false
    t.string "monitor_type"
    t.string "url"
    t.string "hostname"
    t.integer "port"
    t.jsonb "tags", default: [], null: false
    t.integer "status"
    t.float "response_time_ms"
    t.jsonb "uptime", default: {}, null: false
    t.jsonb "average_response_ms", default: {}, null: false
    t.integer "cert_days_remaining"
    t.boolean "cert_valid"
    t.bigint "server_id"
    t.string "matched_by"
    t.string "matched_address"
    t.datetime "status_changed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["monitor_id"], name: "index_uptime_kuma_monitors_on_monitor_id", unique: true
    t.index ["server_id"], name: "index_uptime_kuma_monitors_on_server_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "viewer", null: false
    t.datetime "deactivated_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.text "otp_secret"
    t.datetime "otp_enabled_at"
    t.jsonb "otp_backup_codes", default: [], null: false
    t.integer "otp_last_used_at"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.string "locale"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "vulnerabilities", force: :cascade do |t|
    t.string "source", null: false
    t.string "release", null: false
    t.string "package", null: false
    t.string "cve", null: false
    t.string "fixed_version"
    t.string "severity", default: "unknown", null: false
    t.string "description"
    t.index ["cve"], name: "index_vulnerabilities_on_cve"
    t.index ["source", "release", "package", "cve"], name: "index_vulnerabilities_uniqueness", unique: true
  end

  create_table "vulnerability_feeds", force: :cascade do |t|
    t.string "source", null: false
    t.datetime "refreshed_at"
    t.string "origin"
    t.integer "entries_count", default: 0, null: false
    t.jsonb "releases", default: [], null: false
    t.datetime "failed_at"
    t.string "last_error"
    t.index ["source"], name: "index_vulnerability_feeds_on_source", unique: true
  end

  add_foreign_key "account_snapshots", "servers", on_delete: :cascade
  add_foreign_key "activities", "public_keys", on_delete: :nullify
  add_foreign_key "activities", "servers", on_delete: :nullify
  add_foreign_key "activities", "users", on_delete: :nullify
  add_foreign_key "background_task_items", "background_tasks", on_delete: :cascade
  add_foreign_key "background_task_items", "servers", on_delete: :nullify
  add_foreign_key "background_tasks", "automations", on_delete: :nullify
  add_foreign_key "background_tasks", "users", on_delete: :nullify
  add_foreign_key "dns_links", "servers", on_delete: :cascade
  add_foreign_key "dns_links", "users", on_delete: :nullify
  add_foreign_key "dns_records", "servers", on_delete: :nullify
  add_foreign_key "integration_links", "integrations", on_delete: :cascade
  add_foreign_key "integration_links", "servers", on_delete: :cascade
  add_foreign_key "integration_links", "users", on_delete: :nullify
  add_foreign_key "inventory_health_samples", "servers", on_delete: :cascade
  add_foreign_key "inventory_packages", "servers", on_delete: :cascade
  add_foreign_key "inventory_snapshots", "servers", on_delete: :cascade
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "invitations", "users", on_delete: :nullify
  add_foreign_key "key_rotation_steps", "key_rotations", on_delete: :cascade
  add_foreign_key "key_rotation_steps", "servers", on_delete: :nullify
  add_foreign_key "key_rotations", "ssh_keys", column: "new_key_id", on_delete: :nullify
  add_foreign_key "key_rotations", "ssh_keys", column: "old_key_id", on_delete: :nullify
  add_foreign_key "key_rotations", "users", column: "started_by_id", on_delete: :nullify
  add_foreign_key "notification_batches", "notification_channels", on_delete: :cascade
  add_foreign_key "ovh_resources", "servers", on_delete: :nullify
  add_foreign_key "server_group_memberships", "server_groups", on_delete: :cascade
  add_foreign_key "server_group_memberships", "servers", on_delete: :cascade
  add_foreign_key "server_notes", "servers", on_delete: :cascade
  add_foreign_key "server_notes", "users", on_delete: :nullify
  add_foreign_key "server_vulnerabilities", "servers", on_delete: :cascade
  add_foreign_key "temporary_accesses", "public_keys", on_delete: :nullify
  add_foreign_key "temporary_accesses", "servers", on_delete: :cascade
  add_foreign_key "uptime_kuma_monitors", "servers", on_delete: :nullify
end
