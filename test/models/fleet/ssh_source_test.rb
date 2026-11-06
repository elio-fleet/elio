require "test_helper"

class SshSourceTest < ActiveSupport::TestCase
  test "an address or a network, normalized; anything else is refused" do
    assert_equal "203.0.113.5", SshSource.create!(name: "Elio", cidr: " 203.0.113.5/32 ").cidr
    assert_equal "198.51.100.0/24", SshSource.create!(name: "Office", cidr: "198.51.100.17/24").cidr
    assert_equal "2001:db8::/32", SshSource.create!(name: "V6", cidr: "2001:DB8::/32").cidr
    assert SshSource.find_by!(name: "V6").ipv6?

    [ "", "elio.example.com", "300.1.1.1", "1.2.3.4; rm -rf /" ].each do |value|
      source = SshSource.new(name: "Bad", cidr: value)
      assert_not source.valid?, value
      assert source.errors.added?(:cidr, :invalid), value
    end
  end

  test "a unique name, a comment safe for ufw" do
    SshSource.create!(name: "Coolify", cidr: "203.0.113.6")
    assert_not SshSource.new(name: "coolify", cidr: "203.0.113.7").valid?
    assert_equal "Bureau dAnna ok", SshSource.new(name: "Bureau d'Anna 'ok'", cidr: "1.1.1.1").comment_name
  end

  test "moves up and down" do
    a, b, c = %w[A B C].each_with_index.map { |name, index| SshSource.create!(name: name, cidr: "203.0.113.#{index + 1}", position: index) }
    c.move!(-1)
    assert_equal %w[A C B], SshSource.ordered.pluck(:name)
    a.move!(-1)
    assert_equal %w[A C B], SshSource.ordered.pluck(:name)
    a.move!(1)
    assert_equal %w[C A B], SshSource.ordered.pluck(:name)
    assert b
  end

  test "the sources of a server: the choices of its groups, the whole list otherwise" do
    elio = SshSource.create!(name: "Elio", cidr: "203.0.113.5", position: 0)
    office = SshSource.create!(name: "Office", cidr: "198.51.100.0/24", position: 1)
    server = servers(:db) # Production
    assert_equal [ elio, office ], server.ssh_sources
    assert_empty server.ssh_source_groups

    server_groups(:production).update!(ssh_source_ids: [ office.id.to_s, "" ])
    assert_equal [ office.id ], server_groups(:production).reload.ssh_source_ids
    assert_equal [ office ], server.reload.ssh_sources
    assert_equal [ server_groups(:production) ], server.ssh_source_groups

    server.server_groups << server_groups(:staging)
    server_groups(:staging).update!(ssh_source_ids: [ elio.id ])
    assert_equal [ elio, office ], server.reload.ssh_sources

    server_groups(:production).update!(ssh_source_ids: [ 999_999 ])
    assert_empty server_groups(:production).reload.ssh_source_ids, "an unknown source is not kept: it would open SSH to the whole list"

    SshSource.delete_all
    assert_empty servers(:backup).ssh_sources
  end
end
