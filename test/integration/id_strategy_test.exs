defmodule PostgrexPubsub.IdStrategyIntegrationTest do
  use PostgrexPubsub.IntegrationCase, async: false

  alias PostgrexPubsub.IdStrategy
  alias PostgrexPubsub.ListenerFixtures.IdListener
  alias PostgrexPubsub.TestMigrations.IdMigration

  @trigger PostgrexPubsub.IdStrategy.get_trigger_name("widgets")

  setup do
    install_trigger(IdMigration, 3, @trigger)
    start_listener(IdListener)
    :ok
  end

  test "an insert reaches the listener with only table, type and id" do
    %{rows: [[id]]} =
      TestRepo.query!("INSERT INTO widgets (name) VALUES ('first') RETURNING id")

    assert_receive {:mutation, event}, 5_000

    assert %{"table" => "widgets", "type" => "INSERT", "id" => ^id} = event

    # The whole point of this strategy: no row data, to stay under the 8000-byte
    # pg_notify payload limit.
    assert Map.keys(event) |> Enum.sort() == ["id", "table", "type"]
  end

  test "an update reports the id without row data" do
    %{rows: [[id]]} =
      TestRepo.query!("INSERT INTO widgets (name) VALUES ('before') RETURNING id")

    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000

    TestRepo.query!("UPDATE widgets SET name = 'after' WHERE id = $1", [id])

    assert_receive {:mutation, %{"type" => "UPDATE", "id" => ^id} = event}, 5_000
    refute Map.has_key?(event, "new_row_data")
  end

  test "a delete reports the id of the removed row" do
    %{rows: [[id]]} =
      TestRepo.query!("INSERT INTO widgets (name) VALUES ('doomed') RETURNING id")

    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000

    TestRepo.query!("DELETE FROM widgets WHERE id = $1", [id])

    assert_receive {:mutation, %{"type" => "DELETE", "id" => ^id}}, 5_000
  end

  test "the migration installed the trigger this strategy names" do
    assert trigger_exists?(IdStrategy.get_trigger_name("widgets"))
  end
end
