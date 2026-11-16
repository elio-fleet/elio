require "test_helper"

class ServerScansControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  test "requires authentication" do
    post server_scans_path
    assert_redirected_to new_user_session_path
    assert_no_enqueued_jobs
  end

  test "enqueues a scan of every server" do
    sign_in users(:one)

    post server_scans_path, headers: { "HTTP_REFERER" => servers_url }

    assert_enqueued_jobs 3, only: ScanServerJob
    task = BackgroundTask.sole
    assert_equal [ "keys_scan", "Scan des clés (3 serveurs)", 3 ], [ task.kind, task.label, task.items.count ]
    assert_redirected_to task_path(task)
    assert_equal "Scan des clés lancé.", flash[:notice]
  end

  test "scans the keys of the ticked servers only" do
    sign_in users(:operator)

    post server_scans_path, params: { server_ids: [ servers(:web).id ] }

    assert_enqueued_jobs 1, only: ScanServerJob
    assert_equal [ "Scan des clés (1 serveur)", [ servers(:web) ] ], [ BackgroundTask.sole.label, BackgroundTask.sole.items.map(&:server) ]
  end
end
