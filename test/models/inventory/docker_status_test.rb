require "test_helper"

class Inventory::DockerStatusTest < ActiveSupport::TestCase
  setup { @server = servers(:web) }

  def container(name, state: "running", **extra) = { "name" => name, "state" => state }.merge(extra.stringify_keys)

  def evaluate(containers, booted_at: nil, collected_at: Time.current)
    @server.inventory_snapshots.find_or_initialize_by(category: "docker")
           .update!(status: "ok", collected_at: collected_at, checked_at: collected_at,
                    data: { "docker" => "ok", "images" => [], "containers" => containers, "booted_at" => booted_at&.utc&.iso8601 }.compact)
    Inventory::DockerStatus.evaluate(@server.reload)
  end

  def texts(result) = result.reasons.map(&:text)

  test "several containers with the same problem: their count and their first names" do
    names = %w[a b c d e f g]
    result = evaluate(names.map { |name| container(name, health: "unhealthy") } + [ container("api", looping: true), container("job", looping: true) ])

    assert_equal "crit", result.state
    assert_equal [ "2 conteneurs redémarrent en boucle : api, job", "7 conteneurs en mauvaise santé : a, b, c, d, e, …" ], texts(result)
  end

  test "an expected container that does not run: missing, stopped or paused; a restarting one is a loop" do
    @server.update!(expected_containers: "web, db")
    assert_equal "ok", evaluate([ container("web"), container("db") ]).state

    result = evaluate([ container("web"), container("db", state: "exited") ])
    assert_equal [ "crit", [ "Conteneur attendu db arrêté ou absent" ] ], [ result.state, texts(result) ]
    assert_equal [ "2 conteneurs attendus arrêtés ou absents : web, db" ], texts(evaluate([ container("web", state: "paused") ]))
    assert_equal [ "Conteneur web redémarre en boucle" ], texts(evaluate([ container("web", state: "restarting", looping: true), container("db") ]))
  end

  test "just after the host booted, containers still starting are not a problem yet" do
    @server.update!(expected_containers: "web, db")
    starting = [ container("web", health: "unhealthy"), container("db", state: "exited") ]

    assert_equal [ "ok", [] ], evaluate(starting, booted_at: 3.minutes.ago).then { |result| [ result.state, texts(result) ] }
    assert_equal 2, evaluate(starting, booted_at: 20.minutes.ago).reasons.size
    assert_equal 2, evaluate(starting).reasons.size, "boot time unknown (collected before Elio read it)"
  end

  test "one more container with the same problem is not a new problem" do
    previous = [ Inventory::HealthStatus.reason("crit", :containers_unhealthy, count: 2, containers: %w[a b]).to_h ]
    current = [ Inventory::HealthStatus.reason("crit", :containers_unhealthy, count: 3, containers: %w[a b c]).to_h ]

    assert_empty Inventory::HealthStatus.new_reasons(previous, current)
  end

  test "a reason about several containers stored before they were named is still readable" do
    assert_equal "3 conteneurs en mauvaise santé : …", Inventory::HealthStatus.text({ "key" => "health.containers_unhealthy", "params" => { "count" => 3 } })
  end
end
