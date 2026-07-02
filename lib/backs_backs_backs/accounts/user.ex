defmodule BacksBacksBacks.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  schema "users" do
    field :public_id, :string
    field :github_id, :string
    field :login, :string
    field :name, :string
    field :avatar_url, :string
    field :last_login_at, :utc_datetime_usec
    field :last_tab_organization_signature, :string
    field :last_tab_organization_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def github_changeset(user, attrs) do
    user
    |> cast(attrs, [:public_id, :github_id, :login, :name, :avatar_url, :last_login_at])
    |> validate_required([:public_id, :github_id, :login, :last_login_at])
    |> validate_length(:public_id, max: 64)
    |> validate_length(:github_id, max: 64)
    |> validate_length(:login, max: 128)
    |> validate_length(:name, max: 256)
    |> validate_length(:avatar_url, max: 1024)
    |> unique_constraint(:public_id)
    |> unique_constraint(:github_id)
  end

  def organization_signature_changeset(user, attrs) do
    user
    |> cast(attrs, [:last_tab_organization_signature, :last_tab_organization_at])
    |> validate_length(:last_tab_organization_signature, max: 128)
  end
end
