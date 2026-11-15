require "test_helper"

class ServerSshDiagnosesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier
  include TcpHelpers
  include StubHelpers

  setup do
    # A closed local port: the diagnosis never leaves the machine.
    Server.update_all(host: "127.0.0.1", port: closed_port)
  end

  def frame_id = dom_id(servers(:web), :ssh_check)
  def step(key, status, **options) = Ssh::Diagnosis::Step.new(key: key, status: status, **options)

  test "requires authentication" do
    get server_ssh_diagnosis_path(servers(:web))
    assert_redirected_to new_user_session_path
  end

  test "renders every step in the SSH frame, the failed one with its fix, and records nothing" do
    sign_in users(:viewer)

    get server_ssh_diagnosis_path(servers(:web))

    assert_response :success
    assert_select "turbo-frame##{frame_id}" do
      assert_select ".ssh-diagnosis-result", text: "Échec : Port SSH ouvert"
      assert_select ".ssh-diagnosis-step", 6
      assert_select ".ssh-diagnosis-step[data-step=dns][data-status=ok] .ssh-diagnosis-detail", "Une adresse IP, rien à résoudre."
      assert_select ".ssh-diagnosis-step[data-step=tcp][data-status=failed] .ssh-diagnosis-fix", text: /Rien n'écoute sur le port #{servers(:web).reload.port}/
      assert_select ".ssh-diagnosis-step[data-status=skipped]", 4
      assert_select "a.health-refresh[href=?]", server_ssh_check_path(servers(:web))
    end
    assert_nil servers(:web).reload.ssh_ok
  end

  test "a refused key shows the key install hint, a changed host key the review" do
    sign_in users(:one)
    refused = Ssh::Diagnosis::Result.new(steps: [ step(:dns, :ok), step(:host_key, :ok), step(:authentication, :failed, detail: "x", reason: :key_refused) ])

    stub_method(Ssh::Diagnosis, :call, refused) { get server_ssh_diagnosis_path(servers(:web)) }

    assert_select ".ssh-diagnosis-step[data-step=authentication] .ssh-setup-hint textarea", text: /authorized_keys/

    host_key = { new: "SHA256:new", new_type: "ssh-ed25519", known: [ Ssh::KnownHosts::Entry.new(type: "ssh-ed25519", fingerprint: "SHA256:old") ], new_algorithm: false }
    changed = Ssh::Diagnosis::Result.new(steps: [ step(:host_key, :failed, detail: "x", reason: :host_key_changed, host_key: host_key) ])

    stub_method(Ssh::Diagnosis, :call, changed) { get server_ssh_diagnosis_path(servers(:web)) }

    assert_select ".ssh-diagnosis-step[data-step=host_key] .host-key-changed .host-key-new", "ssh-ed25519 SHA256:new"
    assert_select ".ssh-setup-hint", 0
  end

  test "a server without sudo passes with a warning on the root access" do
    sign_in users(:one)
    result = Ssh::Diagnosis::Result.new(steps: [ step(:authentication, :ok), step(:sudo, :warn, detail: "deploy ne peut pas", fix: :sudo) ])

    stub_method(Ssh::Diagnosis, :call, result) { get server_ssh_diagnosis_path(servers(:web)) }

    assert_select ".ssh-diagnosis-result", "Toutes les étapes passent"
    assert_select ".ssh-diagnosis-step[data-step=sudo][data-status=warn] .ssh-diagnosis-fix", text: /sudo sans mot de passe/
  end

  test "the SSH check links to the diagnosis, failed or not" do
    sign_in users(:one)

    get server_ssh_check_path(servers(:web))
    assert_select "turbo-frame##{frame_id} a.ssh-diagnose[href=?]", server_ssh_diagnosis_path(servers(:web))

    ok = Ssh::Check::Result.new(success: true, message: "ok", details: "ok")
    stub_method(Ssh::Check, :call, ok) { get server_ssh_check_path(servers(:web)) }
    assert_select "turbo-frame##{frame_id} a.ssh-diagnose[href=?]", server_ssh_diagnosis_path(servers(:web))
  end
end
