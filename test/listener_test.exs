defmodule PostgrexPubsub.ListenerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias PostgrexPubsub.ListenerFixtures.PayloadListener
  alias PostgrexPubsub.ListenerFixtures.RaisingListener
  alias PostgrexPubsub.ListenerFixtures.Relay

  # No database here: only init/1 needs a live connection, so every other part of
  # the injected GenServer is exercised by calling it directly.

  describe "child_spec/1" do
    test "is supervisable under the module's own name" do
      spec = PayloadListener.child_spec([])

      assert spec.id == PayloadListener
      assert spec.restart == :permanent
    end

    test "starts on the default channel, registered by module name" do
      assert %{start: {PayloadListener, :start_link, ["pg_mutations", [name: PayloadListener]]}} =
               PayloadListener.child_spec([])
    end
  end

  describe "handle_info/2 with a notification" do
    setup do
      Relay.register(PayloadListener)
      :ok
    end

    test "decodes the payload and hands it to handle_mutation_event/1" do
      payload = Jason.encode!(%{"table" => "widgets", "type" => "INSERT", "id" => 7})

      assert {:noreply, :event_handled} =
               PayloadListener.handle_info(
                 {:notification, self(), make_ref(), "pg_mutations", payload},
                 :any_state
               )

      assert_receive {:mutation, %{"table" => "widgets", "type" => "INSERT", "id" => 7}}
    end

    test "survives malformed JSON instead of crashing the listener" do
      log =
        capture_log(fn ->
          assert {:noreply, :event_error} =
                   PayloadListener.handle_info(
                     {:notification, self(), make_ref(), "pg_mutations", "not json"},
                     :any_state
                   )
        end)

      assert log =~ "failed with error"
      refute_receive {:mutation, _}
    end

    test "survives a handler that raises" do
      payload = Jason.encode!(%{"id" => 1})

      log =
        capture_log(fn ->
          assert {:noreply, :event_error} =
                   RaisingListener.handle_info(
                     {:notification, self(), make_ref(), "pg_mutations", payload},
                     :any_state
                   )
        end)

      assert log =~ "failed with error"
    end
  end

  describe "handle_info/2 with anything else" do
    test "ignores unrecognised messages" do
      assert {:noreply, :event_received} =
               PayloadListener.handle_info(:some_other_message, :any_state)
    end

    test "does not invoke the mutation handler" do
      Relay.register(PayloadListener)
      PayloadListener.handle_info({:not_a_notification, "x"}, :any_state)
      refute_receive {:mutation, _}
    end
  end
end
