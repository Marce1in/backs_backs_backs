defmodule BacksBacksBacks.Repo.Migrations.AddGithubUsersAndScopeTabSync do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :public_id, :string, null: false
      add :github_id, :string, null: false
      add :login, :string, null: false
      add :name, :string
      add :avatar_url, :string
      add :last_login_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:public_id])
    create unique_index(:users, [:github_id])

    execute "DELETE FROM synced_tabs"
    execute "DELETE FROM synced_tab_groups"
    execute "DELETE FROM sync_clients"

    drop_if_exists unique_index(:sync_clients, [:client_id])
    drop_if_exists unique_index(:synced_tab_groups, [:group_key])
    drop_if_exists unique_index(:synced_tabs, [:tab_key])

    alter table(:sync_clients) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    alter table(:synced_tab_groups) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    alter table(:synced_tabs) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    create unique_index(:sync_clients, [:user_id, :client_id])
    create unique_index(:synced_tab_groups, [:user_id, :group_key])
    create unique_index(:synced_tabs, [:user_id, :tab_key])
    create index(:synced_tabs, [:user_id, :fingerprint])
    create index(:synced_tabs, [:user_id, :group_key])
  end
end
