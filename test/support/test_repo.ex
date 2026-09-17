defmodule PostgrexPubsub.TestRepo do
  @moduledoc """
  Repo used by the test suite.

  Serves two purposes: `Ecto.Migrator` needs a real repo to run the library's
  migration macros against, and `PostgrexPubsub.Listener` calls `config/0` on
  whatever module is passed as `repo:` — a real repo satisfies that directly, so
  no stub is needed.
  """

  use Ecto.Repo,
    otp_app: :postgrex_pubsub,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Connection settings, taken from the standard PG* environment variables so the
  suite can point at a different server without code changes.
  """
  def test_config do
    [
      hostname: System.get_env("PGHOST", "localhost"),
      username: System.get_env("PGUSER") || System.get_env("USER"),
      password: System.get_env("PGPASSWORD"),
      port: String.to_integer(System.get_env("PGPORT", "5432")),
      database: System.get_env("PGDATABASE_TEST", "postgrex_pubsub_test"),
      pool_size: 2,
      log: false
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
