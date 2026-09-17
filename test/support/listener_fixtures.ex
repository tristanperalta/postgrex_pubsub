defmodule PostgrexPubsub.ListenerFixtures do
  @moduledoc """
  Listener modules used across the suite.

  Each forwards decoded mutation events to a test process registered under a
  known name, so a test can `assert_receive` on them.
  """

  defmodule Relay do
    @moduledoc "Registry of where a fixture listener should forward events."

    def target_name(module), do: Module.concat(module, "Target")

    def register(module), do: Process.register(self(), target_name(module))

    def forward(module, event) do
      case Process.whereis(target_name(module)) do
        nil -> :ok
        pid -> send(pid, {:mutation, event})
      end
    end
  end

  defmodule PayloadListener do
    use PostgrexPubsub.Listener, repo: PostgrexPubsub.TestRepo

    def handle_mutation_event(event),
      do: PostgrexPubsub.ListenerFixtures.Relay.forward(__MODULE__, event)
  end

  defmodule IdListener do
    use PostgrexPubsub.Listener, repo: PostgrexPubsub.TestRepo

    def handle_mutation_event(event),
      do: PostgrexPubsub.ListenerFixtures.Relay.forward(__MODULE__, event)
  end

  defmodule RaisingListener do
    @moduledoc "Handler that always raises, to exercise the catch clause."
    use PostgrexPubsub.Listener, repo: PostgrexPubsub.TestRepo

    def handle_mutation_event(_event), do: raise("boom")
  end
end
