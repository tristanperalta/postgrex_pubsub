defmodule PostgrexPubsubTest do
  use ExUnit.Case, async: false

  alias PostgrexPubsub.IdStrategy
  alias PostgrexPubsub.PayloadStrategy

  # These assert on substrings rather than whole strings: the SQL is built with
  # interpolated multi-line literals, so exact matches would break on any
  # reindentation without the behaviour having changed.

  describe "default_channel/0" do
    setup do
      original = Application.get_env(:postgrex_pubsub, :channel)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:postgrex_pubsub, :channel)
          value -> Application.put_env(:postgrex_pubsub, :channel, value)
        end
      end)

      :ok
    end

    test "falls back to pg_mutations when unconfigured" do
      Application.delete_env(:postgrex_pubsub, :channel)
      assert PostgrexPubsub.default_channel() == "pg_mutations"
    end

    test "uses the configured channel when set" do
      Application.put_env(:postgrex_pubsub, :channel, "custom_channel")
      assert PostgrexPubsub.default_channel() == "custom_channel"
    end
  end

  describe "create_table_mutation_trigger_sql/3" do
    setup do
      %{sql: PostgrexPubsub.create_table_mutation_trigger_sql("users", "my_trigger", "my_fn")}
    end

    test "creates the named trigger on the named table", %{sql: sql} do
      assert sql =~ "CREATE TRIGGER my_trigger"
      assert sql =~ "ON users"
    end

    test "fires after every mutation, for each row", %{sql: sql} do
      assert sql =~ "AFTER INSERT OR UPDATE OR DELETE"
      assert sql =~ "FOR EACH ROW"
    end

    test "executes the given procedure", %{sql: sql} do
      assert sql =~ "EXECUTE PROCEDURE my_fn();"
    end
  end

  describe "PayloadStrategy" do
    test "function_name/0 is stable" do
      assert PayloadStrategy.function_name() == "broadcast_payload_changes"
    end

    test "get_trigger_name/1 is derived from the table" do
      assert PayloadStrategy.get_trigger_name("users") ==
               "notify_users_payload_changes_trigger"
    end

    test "the function notifies the given channel" do
      sql = PayloadStrategy.create_postgres_broadcast_payload_function_sql("my_channel")

      assert sql =~ "CREATE OR REPLACE FUNCTION broadcast_payload_changes()"
      assert sql =~ "LANGUAGE plpgsql"
      assert sql =~ "pg_notify("
      assert sql =~ "'my_channel'"
    end

    test "the payload carries the full row on both sides" do
      sql = PayloadStrategy.create_postgres_broadcast_payload_function_sql("c")

      assert sql =~ "'table', TG_TABLE_NAME"
      assert sql =~ "'type', TG_OP"
      assert sql =~ "'id', current_row.id"
      assert sql =~ "'new_row_data', row_to_json(NEW)"
      assert sql =~ "'old_row_data', row_to_json(OLD)"
    end
  end

  describe "IdStrategy" do
    test "function_name/0 is stable" do
      assert IdStrategy.function_name() == "broadcast_id_changes"
    end

    test "get_trigger_name/1 is derived from the table" do
      assert IdStrategy.get_trigger_name("users") == "notify_users_id_changes_trigger"
    end

    test "the function notifies the given channel" do
      sql = IdStrategy.create_postgres_broadcast_id_function_sql("my_channel")

      assert sql =~ "CREATE OR REPLACE FUNCTION broadcast_id_changes()"
      assert sql =~ "LANGUAGE plpgsql"
      assert sql =~ "'my_channel'"
    end

    test "the payload omits row data, which is the point of this strategy" do
      sql = IdStrategy.create_postgres_broadcast_id_function_sql("c")

      assert sql =~ "'id', current_row.id"
      refute sql =~ "new_row_data"
      refute sql =~ "old_row_data"
    end

    test "uses a different trigger and function name than PayloadStrategy" do
      refute IdStrategy.function_name() == PayloadStrategy.function_name()

      refute IdStrategy.get_trigger_name("users") ==
               PayloadStrategy.get_trigger_name("users")
    end
  end
end
