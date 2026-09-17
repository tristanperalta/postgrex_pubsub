# The library logs a debug line per listener start; quiet it so failures stand out.
Logger.configure(level: :warning)

alias PostgrexPubsub.TestRepo
alias PostgrexPubsub.TestMigrations

config = TestRepo.test_config()
Application.put_env(:postgrex_pubsub, TestRepo, config)

# The listener hardcodes the "pg_mutations" channel (lib/listener.ex:7) while the
# trigger SQL reads this key. They must agree or no notification is ever received.
Application.delete_env(:postgrex_pubsub, :channel)

defmodule TestSetup do
  @moduledoc false

  def reachable?(config) do
    # A plain TCP probe, because Postgrex connects lazily: start_link/1 succeeds
    # against an unroutable host and the failure would only surface later, as a
    # pool timeout in the middle of the suite.
    host = to_charlist(config[:hostname] || "localhost")
    port = config[:port] || 5432

    case :gen_tcp.connect(host, port, [:binary, active: false], 2_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  catch
    _type, _error -> false
  end

  def prepare(config) do
    # `storage_up/1` returns {:error, :already_up} when the database survived a
    # previous run, which is a success for our purposes.
    case Ecto.Adapters.Postgres.storage_up(config) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "could not create test database: #{inspect(reason)}"
    end

    {:ok, _} = PostgrexPubsub.TestRepo.start_link(config)
    Ecto.Migrator.up(PostgrexPubsub.TestRepo, 1, TestMigrations.CreateWidgets, log: false)
    :ok
  end
end

if TestSetup.reachable?(config) do
  TestSetup.prepare(config)
  ExUnit.start()
else
  IO.puts("""
  \n[postgrex_pubsub] No Postgres reachable at \
  #{config[:hostname]}:#{config[:port]} — skipping integration tests.
  Run them with a server available, or: mix test --only integration\
  """)

  ExUnit.start(exclude: [:integration])
end
