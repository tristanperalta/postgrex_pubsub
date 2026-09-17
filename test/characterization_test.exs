defmodule PostgrexPubsub.CharacterizationTest do
  use ExUnit.Case, async: false

  alias PostgrexPubsub.ListenerFixtures.PayloadListener

  # This records CURRENT behaviour of a known rough edge. It is not an assertion
  # that the behaviour is correct. If it is fixed, this test should fail loudly
  # and be rewritten — that is the point of it.

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
      # (lib/listener.ex handle_info clauses). Harmless only because nothing
      # currently reads them.
      assert {:noreply, :event_received} = PayloadListener.handle_info(:other, state)
    end
  end
end
