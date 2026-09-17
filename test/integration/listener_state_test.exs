defmodule PostgrexPubsub.ListenerStateTest do
  use PostgrexPubsub.IntegrationCase, async: false

  alias PostgrexPubsub.ListenerFixtures.PayloadListener
  alias PostgrexPubsub.ListenerFixtures.RaisingListener
  alias PostgrexPubsub.TestMigrations.PayloadMigration

  @trigger PostgrexPubsub.PayloadStrategy.get_trigger_name("widgets")

  # The listener's state is the connection pid, the channel and the subscription
  # ref. Anything that wants to unlisten, resubscribe or inspect the connection
  # needs it, so every handle_info clause must hand it back unchanged.

  setup do
    install_trigger(PayloadMigration, 9, @trigger)
    %{listener: start_listener(PayloadListener)}
  end

  test "init/1 stores the connection pid, channel and subscription ref", %{listener: pid} do
    assert {conn, channel, ref} = :sys.get_state(pid)

    assert is_pid(conn)
    assert Process.alive?(conn)
    assert channel == "pg_mutations"
    assert is_reference(ref)
  end

  test "a handled notification leaves the state untouched", %{listener: pid} do
    before = :sys.get_state(pid)

    TestRepo.query!("INSERT INTO widgets (name) VALUES ('stateful')")
    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000

    assert :sys.get_state(pid) == before
  end

  test "the state survives a sequence of different messages", %{listener: pid} do
    before = :sys.get_state(pid)

    TestRepo.query!("INSERT INTO widgets (name) VALUES ('first')")
    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000
    assert :sys.get_state(pid) == before

    send(pid, :some_other_message)
    assert :sys.get_state(pid) == before

    TestRepo.query!("UPDATE widgets SET name = 'second' WHERE name = 'first'")
    assert_receive {:mutation, %{"type" => "UPDATE"}}, 5_000
    assert :sys.get_state(pid) == before
  end

  test "the connection pid stays reachable through the state", %{listener: pid} do
    TestRepo.query!("INSERT INTO widgets (name) VALUES ('reachable')")
    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000

    # This is the point of keeping the state: an unlisten or reconnect path can
    # still find the connection and subscription after messages have flowed.
    assert {conn, "pg_mutations", ref} = :sys.get_state(pid)
    assert Process.alive?(conn)
    assert :ok = Postgrex.Notifications.unlisten(conn, ref)
  end

  test "a failing handler does not destroy the state", %{listener: _pid} do
    # Started directly rather than through start_listener/1: its handler always
    # raises, so it has no relay target, and the test process can only hold the
    # one name setup/0 already registered.
    raiser = start_supervised!({RaisingListener, []})
    before = :sys.get_state(raiser)

    TestRepo.query!("INSERT INTO widgets (name) VALUES ('boom')")

    # The handler raises and the catch clause logs, but the listener keeps both
    # its state and its subscription.
    Process.sleep(200)
    assert :sys.get_state(raiser) == before
    assert Process.alive?(raiser)
  end
end
