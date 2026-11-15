require "test_helper"

class ServerSortTest < ActiveSupport::TestCase
  def with_health(name, data)
    servers(name).inventory_snapshots.create!(category: "health", status: "ok", data: data, collected_at: Time.current, checked_at: Time.current)
    servers(name)
  end

  test "an unknown column sorts nothing; figures start with the biggest, the name with A" do
    assert_not ServerSort.new("password", "asc").active?
    assert_equal "desc", ServerSort.new("disk", nil).direction
    assert_equal "asc", ServerSort.new("name", nil).direction
    assert_equal "desc", ServerSort.new("disk", "sideways").direction
  end

  test "a click on the current column reverses it, on another one starts from its default" do
    sort = ServerSort.new("disk", "desc")
    assert_equal "asc", sort.next_direction("disk")
    assert_equal "desc", sort.next_direction("memory")
    assert_equal "asc", sort.next_direction("name")
    assert_equal "desc", ServerSort.new(nil, nil).next_direction("load")
  end

  test "equal figures by name, unknown ones last, updates: the security ones first" do
    a = with_health(:web, "updates" => { "total" => 9, "security" => 0 }, "memory" => { "used_percent" => 50 })
    b = with_health(:db, "updates" => { "total" => 1, "security" => 1 }, "memory" => { "used_percent" => 50 })
    c = servers(:backup)

    assert_equal [ b, a, c ], ServerSort.new("updates", nil).apply([ a, b, c ])
    assert_equal [ a, b, c ], ServerSort.new("updates", "asc").apply([ c, b, a ])
    assert_equal [ b, a, c ], ServerSort.new("memory", nil).apply([ c, a, b ]), "Database before Web"
  end
end
