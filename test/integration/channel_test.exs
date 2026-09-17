defmodule PostgrexPubsub.ChannelIntegrationTest do
  use PostgrexPubsub.IntegrationCase, async: false

  alias PostgrexPubsub.ListenerFixtures.PayloadListener
  alias PostgrexPubsub.TestMigrations.PayloadMigration

  @trigger PostgrexPubsub.PayloadStrategy.get_trigger_name("widgets")

  setup do
    original = Application.get_env(:postgrex_pubsub, :channel)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:postgrex_pubsub, :channel)
        value -> Application.put_env(:postgrex_pubsub, :channel, value)
      end
    end)

    :ok
  end

  test "a configured channel is used by both the trigger and the listener" do
    # Must be set before the migration runs: the channel is baked into the
    # generated trigger function at migration time.
    Application.put_env(:postgrex_pubsub, :channel, "custom_mutations")

    install_trigger(PayloadMigration, 7, @trigger)
    start_listener(PayloadListener)

    %{rows: [[id]]} =
      TestRepo.query!("INSERT INTO widgets (name) VALUES ('routed') RETURNING id")

    assert_receive {:mutation, %{"type" => "INSERT", "id" => ^id}}, 5_000
  end

  test "an explicitly pinned channel overrides the application setting" do
    Application.put_env(:postgrex_pubsub, :channel, "fixed_channel")

    install_trigger(PayloadMigration, 8, @trigger)
    start_listener(PostgrexPubsub.ListenerFixtures.FixedChannelListener)

    TestRepo.query!("INSERT INTO widgets (name) VALUES ('pinned')")

    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000
  end
end
