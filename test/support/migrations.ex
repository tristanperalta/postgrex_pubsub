defmodule PostgrexPubsub.TestMigrations do
  @moduledoc """
  Migrations used by the integration tests.

  `PayloadMigration` and `IdMigration` go through the library's public macros,
  exactly as a consumer would, so the macros themselves are under test.
  """

  defmodule CreateWidgets do
    use Ecto.Migration

    def up do
      create table(:widgets) do
        add(:name, :string)
      end
    end

    def down do
      drop(table(:widgets))
    end
  end

  defmodule PayloadMigration do
    use PostgrexPubsub.BroadcastPayloadMigration, table_name: "widgets"
  end

  defmodule IdMigration do
    use PostgrexPubsub.BroadcastIdMigration, table_name: "widgets"
  end
end
