defmodule PostgrexPubsub.IntegrationCase do
  @moduledoc """
  Case template for tests that talk to a real Postgres.

  Installs one strategy's trigger for the duration of the module and removes it
  afterwards, so the payload and id strategies never both fire on the same row.
  """

  use ExUnit.CaseTemplate

  alias PostgrexPubsub.TestRepo

  using do
    quote do
      import PostgrexPubsub.IntegrationCase

      alias PostgrexPubsub.TestRepo

      @moduletag :integration
      @moduletag timeout: 30_000
    end
  end

  setup do
    TestRepo.query!("DELETE FROM widgets")
    :ok
  end

  @doc "Installs a migration's trigger, removing it when the test finishes."
  def install_trigger(migration, version, trigger_name) do
    drop_trigger(trigger_name)

    # Ecto.Migrator records applied versions and skips them on a rerun, which
    # would leave the trigger uninstalled for every test after the first. Clearing
    # every trigger migration (not just this one) also stops Ecto warning about
    # running an older version after a newer one.
    TestRepo.query!("DELETE FROM schema_migrations WHERE version > 1")
    Ecto.Migrator.up(TestRepo, version, migration, log: false)

    ExUnit.Callbacks.on_exit(fn ->
      drop_trigger(trigger_name)
    end)

    :ok
  end

  @doc """
  Removes a trigger using correct SQL.

  The library's own `delete_trigger/1` cannot be used here: it emits
  `DROP TRIGGER <name>` with no `ON <table>`, which Postgres rejects.
  See the rollback test in `test/integration/migration_test.exs`.
  """
  def drop_trigger(trigger_name) do
    TestRepo.query!("DROP TRIGGER IF EXISTS #{trigger_name} ON widgets")
  end

  @doc "True when a trigger of this name exists on the widgets table."
  def trigger_exists?(trigger_name) do
    %{rows: [[count]]} =
      TestRepo.query!(
        """
        SELECT count(*) FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        WHERE c.relname = 'widgets' AND t.tgname = $1
        """,
        [trigger_name]
      )

    count > 0
  end

  @doc "Starts a fixture listener and routes its events to the calling process."
  def start_listener(module) do
    PostgrexPubsub.ListenerFixtures.Relay.register(module)
    pid = ExUnit.Callbacks.start_supervised!({module, []})

    # The listener subscribes during init/1, which has returned by the time
    # start_supervised! does, so notifications from here on are delivered.
    pid
  end
end
