require "test_helper"

class TaskCancellationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def enqueue = BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire du parc", servers: [ servers(:web), servers(:db) ], user: users(:operator))

  test "an operator cancels the servers still waiting, from the run's page" do
    task = enqueue
    task.items.find_by!(server: servers(:web)).start!
    sign_in users(:operator)

    get task_path(task)
    assert_select "form[action=?][data-turbo-confirm] button.task-cancel", task_cancellation_path(task), text: /Annuler les serveurs en attente/

    post task_cancellation_path(task)

    assert_redirected_to task_path(task)
    assert_equal "Les serveurs en attente sont annulés ; ceux en cours de lecture vont jusqu'au bout.", flash[:notice]
    assert_equal({ "Database" => "failed", "Web" => "running" }, task.items.reload.to_h { |item| [ item.server_name, item.status ] })

    get task_path(task)
    assert_select "button.task-cancel", 0
  end

  test "a run without a server waiting cannot be cancelled" do
    task = enqueue
    task.items.each { |item| item.finish!(:succeeded) }
    sign_in users(:operator)

    post task_cancellation_path(task)

    assert_redirected_to task_path(task)
    assert_equal "Cette exécution n'a plus de serveur en attente.", flash[:alert]
  end

  test "a viewer sees no cancel button" do
    task = enqueue
    sign_in users(:viewer)

    get task_path(task)

    assert_select "button.task-cancel", 0
  end
end
