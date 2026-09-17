defmodule PostgrexPubsub.ListenerStateTest do
  use PostgrexPubsub.IntegrationCase, async: false

  alias PostgrexPubsub.ListenerFixtures.PayloadListener
  alias PostgrexPubsub.TestMigrations.PayloadMigration

  @trigger PostgrexPubsub.PayloadStrategy.get_trigger_name("widgets")

  # These record CURRENT behaviour of a known rough edge, and are not an
  # assertion that it is correct. handle_info/2 returns a status atom in the
  # slot a GenServer treats as its new state, so the {pid, channel, ref} tuple
  # built by init/1 is discarded on the first message. If that is fixed, these
  # tests should fail loudly and be rewritten — that is the point of them.

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

  test "the first notification replaces that tuple with a bare atom", %{listener: pid} do
    assert {_conn, _channel, _ref} = :sys.get_state(pid)

    TestRepo.query!("INSERT INTO widgets (name) VALUES ('stateful')")
    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000

    # The connection pid and subscription ref are now unrecoverable from state.
    assert :sys.get_state(pid) == :event_handled
  end

  test "the loss persists across later messages", %{listener: pid} do
    TestRepo.query!("INSERT INTO widgets (name) VALUES ('first')")
    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000
    assert :sys.get_state(pid) == :event_handled

    # Driven through the real GenServer loop, so each message sees the state the
    # previous one left behind: an atom, never the tuple.
    send(pid, :some_other_message)
    assert :sys.get_state(pid) == :event_received

    TestRepo.query!("UPDATE widgets SET name = 'second' WHERE name = 'first'")
    assert_receive {:mutation, %{"type" => "UPDATE"}}, 5_000
    assert :sys.get_state(pid) == :event_handled
  end

  test "delivery still works despite the discarded state", %{listener: pid} do
    for name <- ~w(one two three) do
      TestRepo.query!("INSERT INTO widgets (name) VALUES ($1)", [name])
      assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000
    end

    # The bug is latent precisely because nothing reads the state back.
    assert Process.alive?(pid)
  end
end
