defmodule PostgrexPubsub.PayloadStrategyIntegrationTest do
  use PostgrexPubsub.IntegrationCase, async: false

  alias PostgrexPubsub.ListenerFixtures.PayloadListener
  alias PostgrexPubsub.PayloadStrategy
  alias PostgrexPubsub.TestMigrations.PayloadMigration

  @trigger PostgrexPubsub.PayloadStrategy.get_trigger_name("widgets")

  setup do
    install_trigger(PayloadMigration, 2, @trigger)
    start_listener(PayloadListener)
    :ok
  end

  test "an insert reaches the listener with the full row" do
    %{rows: [[id]]} =
      TestRepo.query!("INSERT INTO widgets (name) VALUES ('first') RETURNING id")

    assert_receive {:mutation, event}, 5_000

    assert %{"table" => "widgets", "type" => "INSERT", "id" => ^id} = event
    assert event["new_row_data"]["name"] == "first"
  end

  test "on insert, old_row_data mirrors the new row" do
    TestRepo.query!("INSERT INTO widgets (name) VALUES ('mirrored')")

    assert_receive {:mutation, event}, 5_000

    # lib/postgrex_pubsub.ex:35-37 assigns OLD := NEW for inserts, so both sides
    # of the payload carry the same row rather than old_row_data being null.
    assert event["old_row_data"] == event["new_row_data"]
  end

  test "an update carries both the old and the new row" do
    %{rows: [[id]]} =
      TestRepo.query!("INSERT INTO widgets (name) VALUES ('before') RETURNING id")

    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000

    TestRepo.query!("UPDATE widgets SET name = 'after' WHERE id = $1", [id])

    assert_receive {:mutation, %{"type" => "UPDATE"} = event}, 5_000

    assert event["id"] == id
    assert event["old_row_data"]["name"] == "before"
    assert event["new_row_data"]["name"] == "after"
  end

  test "a delete reaches the listener carrying the removed row" do
    %{rows: [[id]]} =
      TestRepo.query!("INSERT INTO widgets (name) VALUES ('doomed') RETURNING id")

    assert_receive {:mutation, %{"type" => "INSERT"}}, 5_000

    TestRepo.query!("DELETE FROM widgets WHERE id = $1", [id])

    assert_receive {:mutation, %{"type" => "DELETE"} = event}, 5_000

    assert event["id"] == id
    assert event["old_row_data"]["name"] == "doomed"
  end

  test "the migration installed the trigger this strategy names" do
    assert trigger_exists?(PayloadStrategy.get_trigger_name("widgets"))
  end
end
