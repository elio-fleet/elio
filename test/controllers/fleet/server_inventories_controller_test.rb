require "test_helper"

class ServerInventoriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  test "requires authentication" do
    post server_inventory_path(servers(:web))
    assert_redirected_to new_user_session_path
  end

  test "starts the inventory of one server in the background, as a task" do
    sign_in users(:operator)

    post server_inventory_path(servers(:web))

    task = BackgroundTask.sole
    item = task.items.sole
    assert_equal [ "inventory", "Inventaire de « Web »", users(:operator), "queued" ], [ task.kind, task.label, task.user, task.status ]
    assert_equal [ servers(:web), "Web", "queued" ], [ item.server, item.server_name, item.status ]
    assert_enqueued_with(job: Inventory::CollectJob, args: [ servers(:web), { task_item: item } ])
    assert_redirected_to task_path(task)
    assert_equal "Inventaire de « Web » lancé.", flash[:notice]
  end

  test "starts the inventory of every server, one task" do
    sign_in users(:one)

    assert_enqueued_jobs(3, only: Inventory::CollectJob) { post server_inventories_path }

    task = BackgroundTask.sole
    assert_equal [ "Inventaire du parc (3 serveurs)", 3 ], [ task.label, task.items.count ]
    assert_redirected_to task_path(task)
  end

  test "starts the inventory of the ticked servers only" do
    sign_in users(:operator)

    assert_enqueued_jobs(2, only: Inventory::CollectJob) { post server_inventories_path, params: { server_ids: [ servers(:web).id, servers(:db).id ] } }

    task = BackgroundTask.sole
    assert_equal [ "Inventaire de 2 serveurs", [ "Database", "Web" ] ], [ task.label, task.items.map(&:server_name).sort ]
    assert_redirected_to task_path(task)
  end

  test "an empty selection starts nothing" do
    sign_in users(:operator)

    post server_inventories_path, params: { server_ids: [ "" ] }, headers: { "HTTP_REFERER" => servers_url }

    assert_no_enqueued_jobs
    assert_redirected_to servers_url
    assert_equal "Aucun serveur coché.", flash[:alert]
  end

  test "a server already being collected is left out, and alone it leads to the run that collects it" do
    sign_in users(:operator)
    running = BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: [ servers(:web) ])

    assert_enqueued_jobs(2, only: Inventory::CollectJob) { post server_inventories_path }
    task = BackgroundTask.recent.first
    assert_equal [ "Inventaire du parc (2 serveurs)", false ], [ task.label, task.items.map(&:server).include?(servers(:web)) ]
    assert_equal "Inventaire du parc (2 serveurs) lancé. 1 serveur déjà en cours de lecture a été laissé de côté.", flash[:notice]

    assert_no_enqueued_jobs { post server_inventory_path(servers(:web)) }
    assert_redirected_to task_path(running)
    assert_equal "Déjà en cours sur ces serveurs.", flash[:notice]
  end

  test "a keys scan running does not stop an inventory" do
    sign_in users(:operator)
    BackgroundTask.enqueue!(kind: "keys_scan", label: "Scan", servers: [ servers(:web) ])

    assert_enqueued_jobs(1, only: Inventory::CollectJob) { post server_inventory_path(servers(:web)) }
  end

  test "returns 404 for an unknown server" do
    sign_in users(:one)
    post server_inventory_path(server_id: 0)
    assert_response :not_found
  end

  test "the server page offers to refresh the inventory to operators only" do
    sign_in users(:operator)
    get server_path(servers(:web))
    assert_select "form.refresh-inventory[action=?] button", server_inventory_path(servers(:web)), text: /Actualiser l'inventaire/

    sign_in users(:viewer)
    get server_path(servers(:web))
    assert_select "form.refresh-inventory", 0
  end
end
