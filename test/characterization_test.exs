defmodule PostgrexPubsub.CharacterizationTest do
  use ExUnit.Case, async: false

  alias PostgrexPubsub.ListenerFixtures.PayloadListener

  # These record CURRENT behaviour of two known rough edges. They are not
  # assertions that the behaviour is correct. If either is fixed, the matching
  # test should fail loudly and be rewritten — that is the point of it.

  describe "configured channel does not reach the listener" do
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

    test "the trigger SQL follows :channel but child_spec/1 stays on pg_mutations" do
      Application.put_env(:postgrex_pubsub, :channel, "custom_channel")

      # The publishing side picks the config up...
      assert PostgrexPubsub.default_channel() == "custom_channel"

      # ...while the subscribing side is hardcoded at lib/listener.ex:7, because
      # @default_channel is read at macro-expansion time and ignores app env.
      assert %{start: {_, :start_link, ["pg_mutations", _]}} = PayloadListener.child_spec([])

      # Consequence: configuring :channel silently breaks delivery.
      refute PostgrexPubsub.default_channel() ==
               elem(PayloadListener.child_spec([]).start, 2) |> hd()
    end
  end

  describe "handle_info/2 discards the GenServer state" do
    test "the {pid, channel, ref} tuple from init/1 is replaced by a bare atom" do
      state = {self(), "pg_mutations", make_ref()}
      payload = Jason.encode!(%{"id" => 1})

      assert {:noreply, :event_handled} =
               PayloadListener.handle_info(
                 {:notification, self(), make_ref(), "pg_mutations", payload},
                 state
               )

      # The connection pid and subscription ref are gone after the first message
      # (lib/listener.ex:56, :61, :65). Harmless only because nothing reads them.
      assert {:noreply, :event_received} = PayloadListener.handle_info(:other, state)
    end
  end
end
