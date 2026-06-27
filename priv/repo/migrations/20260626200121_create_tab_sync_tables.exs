defmodule BacksBacksBacks.Repo.Migrations.CreateTabSyncTables do
  use Ecto.Migration

  def change do
    create table(:sync_clients) do
      add :client_id, :string, null: false
      add :label, :string, null: false
      add :last_seen_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sync_clients, [:client_id])

    create table(:synced_tab_groups) do
      add :group_key, :string, null: false
      add :title, :string, null: false
      add :color, :string, null: false
      add :position, :integer, null: false, default: 0
      add :last_seen_client_id, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:synced_tab_groups, [:group_key])

    create table(:synced_tabs) do
      add :fingerprint, :string, null: false
      add :url, :string, null: false
      add :title, :string, null: false
      add :position, :integer, null: false, default: 0
      add :group_key, :string
      add :last_seen_client_id, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:synced_tabs, [:fingerprint])
    create index(:synced_tabs, [:group_key])
  end
end
