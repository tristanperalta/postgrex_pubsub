defmodule PostgrexPubsub.Listener do
  @moduledoc """
  A macro for creating a simple listener for postgres changes
  """

  defmacro __using__(opts) do
    opts = Map.new(opts)
    repo_module = Map.get(opts, :repo)
    channel = Map.get(opts, :channel)

    quote do
      use GenServer
      require Logger

      @doc """
      Initialize the GenServer in the supervision tree
      """
      def child_spec(_) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [default_channel(), [name: __MODULE__]]},
          restart: :permanent
        }
      end

      @doc """
      The channel this listener subscribes to.

      Resolved at runtime so it always matches the channel the trigger SQL
      publishes on, which `PostgrexPubsub.default_channel/0` derives from the
      `:postgrex_pubsub, :channel` application setting. A `:channel` option
      given to `use PostgrexPubsub.Listener` overrides both.
      """
      def default_channel do
        unquote(channel) || PostgrexPubsub.default_channel()
      end

      @doc """
      Initialize the activity GenServer
      """
      @spec start_link(String.t(), [any]) :: {:ok, pid}
      def start_link(channel, otp_opts \\ []),
        do: GenServer.start_link(__MODULE__, channel, otp_opts)

      @doc """
      When the GenServer starts subscribe to the given topics
      """
      def init(channel) do
        Logger.debug("Starting #{__MODULE__} with channel subscription: #{channel}")
        pg_config = unquote(repo_module).config()
        {:ok, pid} = Postgrex.Notifications.start_link(pg_config)
        {:ok, ref} = Postgrex.Notifications.listen(pid, channel)
        {:ok, {pid, channel, ref}}
      end

      @doc """
      Listen for changes
      """
      def handle_info({:notification, _pid, _ref, _channel_name, payload}, state) do
        payload
        |> Jason.decode!()
        |> handle_mutation_event()

        {:noreply, state}
      catch
        type, error ->
          exception = Exception.format(type, error, __STACKTRACE__)
          Logger.error("Listener: #{__MODULE__} failed with error: #{exception}")
          {:noreply, state}
      end

      def handle_info(_value, state) do
        {:noreply, state}
      end
    end
  end
end
