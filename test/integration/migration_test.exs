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

  test "down/0 rolls the trigger back" do
    install_trigger(PayloadMigration, 5, @trigger)
    assert trigger_exists?(@trigger)

    Ecto.Migrator.down(TestRepo, 5, PayloadMigration, log: false)

    refute trigger_exists?(@trigger)
  end

  test "up/0 after down/0 reinstalls the trigger" do
    install_trigger(PayloadMigration, 6, @trigger)
    Ecto.Migrator.down(TestRepo, 6, PayloadMigration, log: false)
    refute trigger_exists?(@trigger)

    Ecto.Migrator.up(TestRepo, 6, PayloadMigration, log: false)

    assert trigger_exists?(@trigger)
  end

  defp function_exists?(name) do
    %{rows: [[count]]} =
      TestRepo.query!("SELECT count(*) FROM pg_proc WHERE proname = $1", [name])

    count > 0
  end
end
