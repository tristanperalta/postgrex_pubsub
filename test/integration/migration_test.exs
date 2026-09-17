defmodule PostgrexPubsub.MigrationIntegrationTest do
  use PostgrexPubsub.IntegrationCase, async: false

  alias PostgrexPubsub.PayloadStrategy
  alias PostgrexPubsub.TestMigrations.PayloadMigration

  @trigger PostgrexPubsub.PayloadStrategy.get_trigger_name("widgets")

  test "up/0 installs both the notify function and the trigger" do
    refute trigger_exists?(@trigger)

    install_trigger(PayloadMigration, 4, @trigger)

    assert trigger_exists?(@trigger)
    assert function_exists?(PayloadStrategy.function_name())
  end

  test "down/0 fails: DROP TRIGGER is emitted without its ON clause" do
    install_trigger(PayloadMigration, 5, @trigger)
    assert trigger_exists?(@trigger)

    # Records current behaviour, and is not an endorsement of it.
    # PostgrexPubsub.delete_trigger/1 (lib/postgrex_pubsub.ex:17) builds
    # "DROP TRIGGER <name>" with no "ON <table>", which Postgres rejects as a
    # syntax error, so rolling back either migration macro is impossible.
    # If delete_trigger/1 is fixed, this test should fail and be rewritten to
    # assert that the trigger is actually gone.
    assert_raise Postgrex.Error, ~r/syntax error/, fn ->
      Ecto.Migrator.down(TestRepo, 5, PayloadMigration, log: false)
    end

    assert trigger_exists?(@trigger), "trigger survives the failed rollback"
  end

  defp function_exists?(name) do
    %{rows: [[count]]} =
      TestRepo.query!("SELECT count(*) FROM pg_proc WHERE proname = $1", [name])

    count > 0
  end
end
