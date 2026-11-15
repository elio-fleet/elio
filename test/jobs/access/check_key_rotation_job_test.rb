require "test_helper"

class CheckKeyRotationJobTest < ActiveJob::TestCase
  include StubHelpers

  test "reports each server's dry run to its task item" do
    task = BackgroundTask.enqueue!(kind: "key_rotation_check", label: "Simulation", servers: [ servers(:web), servers(:db) ], user: users(:one))
    results = {
      "Web" => Keys::RotationCheck::Result.new(status: :ready, message: "Prêt"),
      "Database" => Keys::RotationCheck::Result.new(status: :key_refused, message: "Clé SSH refusée par le serveur — x")
    }

    stub_method(Keys::RotationCheck, :call, ->(server, **) { results.fetch(server.name) }) do
      task.items.each { |item| CheckKeyRotationJob.perform_now(item.server, task_item: item) }
    end

    assert_equal [ [ "Database", "failed", "Clé SSH refusée par le serveur — x" ], [ "Web", "succeeded", "Prêt" ] ],
                 task.items.reload.map { |item| [ item.server_name, item.status, item.message ] }
    assert_equal "partial", task.reload.status
  end
end
