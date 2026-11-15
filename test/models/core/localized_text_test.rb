require "test_helper"

class LocalizedTextTest < ActiveSupport::TestCase
  test "a text kept as a key is written in the language of whoever reads it, parts included" do
    value = LocalizedText.dump("automation.results.scanned", done: 3, count: 3, keys: LocalizedText.part("automation.results.new_unknown_keys", count: 0))

    french = LocalizedText.render(value)
    english = I18n.with_locale(:en) { LocalizedText.render(value) }
    assert_match "3/3", french
    assert_not_equal french, english
    assert_match(/server/i, english)
  end

  test "plain and older texts are read as they are" do
    assert_equal "8/8 serveurs inventoriés", LocalizedText.render("8/8 serveurs inventoriés")
    assert_nil LocalizedText.render(nil)
    assert_equal '{"key": broken', LocalizedText.render('{"key": broken')
  end

  test "an automation result and a run label follow the reader" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "inventory_packages" }
    automation.update!(last_result: LocalizedText.dump("automation.results.inventoried", done: 2, count: 2))
    task = BackgroundTask.enqueue!(kind: "automation", label: LocalizedText.part("automation.kinds.inventory_packages.label"), servers: [], automation: automation)

    assert_equal "Inventaire des paquets", task.label
    assert_equal "Inventaire des paquets", task.read_attribute(:label), "the plain label stays for the Journal search"
    I18n.with_locale(:en) do
      assert_equal "Packages inventory", task.reload.label
      assert_match "2/2 servers inventoried", automation.reload.last_result
    end
  end
end
