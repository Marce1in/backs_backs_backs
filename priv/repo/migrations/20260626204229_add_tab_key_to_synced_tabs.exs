defmodule BacksBacksBacks.Repo.Migrations.AddTabKeyToSyncedTabs do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:synced_tabs, [:fingerprint])

    alter table(:synced_tabs) do
      add :tab_key, :string
    end

    execute "UPDATE synced_tabs SET tab_key = fingerprint WHERE tab_key IS NULL"

    create unique_index(:synced_tabs, [:tab_key])
    create index(:synced_tabs, [:fingerprint])
  end

  def down do
    drop_if_exists index(:synced_tabs, [:fingerprint])
    drop_if_exists unique_index(:synced_tabs, [:tab_key])

    alter table(:synced_tabs) do
      remove :tab_key
    end

    create unique_index(:synced_tabs, [:fingerprint])
  end
end
