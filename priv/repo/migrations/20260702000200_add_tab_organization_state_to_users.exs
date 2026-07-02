defmodule BacksBacksBacks.Repo.Migrations.AddTabOrganizationStateToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_tab_organization_signature, :string
      add :last_tab_organization_at, :utc_datetime_usec
    end
  end
end
