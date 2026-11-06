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
    assert_select "form.import-confirm", 0

    post preview_server_import_path, params: { content: "", import_format: "csv" }
    assert_response :unprocessable_entity
    assert_select "#flash .toast-alert", text: /Collez ou choisissez un fichier/
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
