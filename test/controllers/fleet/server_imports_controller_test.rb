require "test_helper"

class ServerImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  CSV_TEXT = "nom,hôte,port,utilisateur,groupes\nAPI,10.0.0.12,22,deploy,Production\nweb,10.0.0.13\nBad,,\n".freeze

  test "requires authentication" do
    get new_server_import_path
    assert_redirected_to new_user_session_path
  end

  test "the form, linked from the servers page" do
    sign_in users(:one)
    get servers_path
    assert_select "a[href=?]", new_server_import_path, text: "Importer des serveurs"

    get new_server_import_path
    assert_response :success
    assert_select "form[action=?][enctype='multipart/form-data'][data-turbo=false]", preview_server_import_path do
      assert_select "input[type=radio][name=import_format][value=csv][checked]"
      assert_select "input[type=radio][name=import_format][value=ssh_config]"
      assert_select "textarea[name=content]"
      assert_select "input[type=file][name=file]"
      assert_select "input[name=default_username][value=root]"
    end
    assert_select "#import-preview", 0
  end

  test "previews the rows without creating anything" do
    sign_in users(:operator)

    assert_no_difference("Server.count") do
      post preview_server_import_path, params: { content: CSV_TEXT, import_format: "csv" }
    end

    assert_response :success
    assert_select "#import-preview" do
      assert_select ".import-counts", text: /1 serveur à importer · 1 doublon ignoré · 1 ligne en erreur/
      assert_select "tr.import-row.is-valid", text: /API.*deploy@10.0.0.12:22.*Production.*À importer/m
      assert_select "tr.import-row.is-duplicate", text: /Doublon de « Web »/
      assert_select "tr.import-row.is-invalid", text: /Hôte/
      assert_select "form.import-confirm[action=?]", server_import_path do
        assert_select "textarea[hidden][name=content]", text: CSV_TEXT
        assert_select "input[type=hidden][name=import_format][value=csv]"
        assert_select "input[type=submit][value=?]", "Importer 1 serveur"
      end
    end
  end

  test "previews an uploaded ssh config file" do
    sign_in users(:one)
    file = Rack::Test::UploadedFile.new(StringIO.new("Host api\n  HostName 10.0.0.12\n"), "text/plain", original_filename: "config")

    post preview_server_import_path, params: { file: file, import_format: "ssh_config", default_username: "admin" }

    assert_select "tr.import-row.is-valid", text: /admin@10.0.0.12:22/
    assert_select "form.import-confirm textarea[name=content]", text: "Host api\n  HostName 10.0.0.12\n"
    assert_select "form.import-confirm input[name=default_username][value=admin]"
  end

  test "no confirm button when nothing is valid, and errors are shown" do
    sign_in users(:one)

    post preview_server_import_path, params: { content: "web,10.0.0.13\n", import_format: "csv" }
    assert_select "form.import-confirm input[type=submit]", 0
    assert_select "form.import-confirm .import-recheck", 0
    assert_select "#collect_inventory", 0

    post preview_server_import_path, params: { content: "", import_format: "csv" }
    assert_response :unprocessable_entity
    assert_select "#flash .toast-alert", text: /Collez ou choisissez un fichier/
  end

  test "the rows in error are fields, checked again once corrected" do
    sign_in users(:one)

    post preview_server_import_path, params: { content: CSV_TEXT, import_format: "csv" }
    assert_select "form.import-confirm[action=?]", server_import_path do
      assert_select "button.import-recheck[formaction=?]", preview_server_import_path
      assert_select "tr.import-row.is-invalid input[type=text][name='rows[2][host]']"
      assert_select "tr.import-row.is-valid input[type=hidden][name='rows[0][host]'][value='10.0.0.12']"
      assert_select "input[type=checkbox][name=collect_inventory][value='1'][checked]"
    end

    rows = { "0" => { line: 2, name: "API", host: "10.0.0.12", port: 22, username: "deploy", groups: "Production" },
             "1" => { line: 3, name: "web", host: "10.0.0.13", port: 22, username: "root", groups: "" },
             "2" => { line: 4, name: "Bad", host: "10.0.0.14", port: 22, username: "root", groups: "New" } }
    assert_no_difference("Server.count") do
      post preview_server_import_path, params: { rows: rows, content: CSV_TEXT, import_format: "csv", collect_inventory: "0" }
    end

    assert_response :success
    assert_select ".import-counts", text: /2 serveurs à importer · 1 doublon ignoré · 0 ligne en erreur/
    assert_select "tr.import-row.is-valid", text: /Bad.*root@10.0.0.14:22.*New/m
    assert_select "input[type=checkbox][name=collect_inventory]:not([checked])"
    assert_select "#content", text: CSV_TEXT
  end

  test "imports the confirmed rows and runs their first inventory when asked" do
    sign_in users(:one)
    rows = { "0" => { line: 2, name: "API", host: "10.0.0.12", port: 22, username: "deploy", groups: "" },
             "1" => { line: 3, name: "Bad", host: "not a host!", port: 22, username: "root", groups: "" } }

    assert_enqueued_jobs 1, only: Inventory::FirstCollectJob do
      assert_difference("Server.count", 1) { post server_import_path, params: { rows: rows, import_format: "csv", collect_inventory: "1" } }
    end
    assert_redirected_to servers_path
    assert_match "Son premier inventaire se lance", flash[:notice]

    assert_no_enqueued_jobs only: Inventory::FirstCollectJob do
      post server_import_path, params: { rows: { "0" => { line: 2, name: "API 2", host: "10.0.0.22" } }, collect_inventory: "0" }
    end
    assert_match "Installez-y la clé", flash[:notice]
  end

  test "an ssh config: ignored options and Include files are shown" do
    sign_in users(:one)

    post preview_server_import_path, params: { content: "Include config.d/*\nHost app\n  HostName 10.0.0.80\n  ProxyJump bastion\n", import_format: "ssh_config" }

    assert_select ".import-includes code", text: "config.d/*"
    assert_select "tr.import-row.is-valid .import-warning", text: /ProxyJump ignoré/
  end

  test "the servers known by the extensions are offered, then previewed" do
    sign_in users(:one)
    get new_server_import_path
    assert_select ".extension-candidates", 0
    assert_select ".import-limits", text: "200 Ko et 500 serveurs au plus par import."

    Integration.find_or_create_by!(kind: "ovh").update_column(:enabled, true)
    OvhResource.create!(kind: "vps", external_id: "vps-1", name: "vps-1", addresses: [ "203.0.113.20" ])
    get new_server_import_path
    assert_select ".extension-candidates", text: /1 serveur connu de OVHcloud n'est pas encore dans Elio/ do
      assert_select "form[action=?] input[name=source][value=extensions]", preview_server_import_path
    end

    post preview_server_import_path, params: { source: "extensions", default_username: "debian" }
    assert_select "tr.import-row.is-valid", text: /vps-1.*debian@203.0.113.20:22/m
    assert_select "#content", text: /name,host,port,user\nvps-1,203.0.113.20,,/
    assert_select ".extension-candidates", 0
  end

  test "imports the valid rows, creates the groups and logs it" do
    sign_in users(:one)

    assert_difference -> { Server.count } => 1, -> { Activity.of_kind(:servers_imported).count } => 1 do
      post server_import_path, params: { content: CSV_TEXT, import_format: "csv" }
    end

    assert_redirected_to servers_path
    assert_match "1 serveur importé", flash[:notice]
    assert_equal [ server_groups(:production) ], Server.find_by!(name: "API").server_groups.to_a
    assert_equal "1 serveur importé (CSV) : API", Activity.last.summary
    assert_equal users(:one), Activity.last.user
  end

  test "an import with nothing valid creates nothing" do
    sign_in users(:one)

    assert_no_difference("Server.count") { post server_import_path, params: { content: "web,10.0.0.13\n", import_format: "csv" } }
    assert_redirected_to new_server_import_path
    assert_equal "Aucun serveur valide à importer.", flash[:alert]
  end

  test "viewers cannot import" do
    sign_in users(:viewer)
    post server_import_path, params: { content: CSV_TEXT, import_format: "csv" }
    assert_response :forbidden
  end
end
