require "application_system_test_case"

class TasksTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:one) }

  test "an inventory started from a server page is followed until it ends" do
    visit server_path(servers(:web))
    click_on "Actualiser l'inventaire"

    assert_selector "h1", text: "Inventaire de « Web »"
    assert_selector "#task-status[data-status=queued]", text: "À venir"
    assert_selector "#flash .toast", text: "Inventaire de « Web » lancé."

    # The jobs do not run in tests: the worker's progress is simulated.
    item = BackgroundTask.sole.items.sole
    item.start!
    assert_selector "#task-status[data-status=running]", text: "En cours", wait: 6

    item.finish!(:failed, "Clé d'Elio refusée")
    assert_selector "#task-status[data-status=failed]", text: "En échec", wait: 6
    assert_selector "tr.task-item", text: "Clé d'Elio refusée"

    click_on "Exécutions" # breadcrumb of the run
    assert_selector "tr.background-task", text: "Inventaire de « Web »"
    click_on "En échec"
    assert_selector "nav.task-filters a[aria-current=true]", text: "En échec"
    assert_selector "tr.background-task", count: 1
  end
end
