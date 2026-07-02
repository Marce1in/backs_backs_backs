defmodule BacksBacksBacks.TabSync.SyncClient do
  use Ecto.Schema

  import Ecto.Changeset

  schema "sync_clients" do
    field :user_id, :id
    field :client_id, :string
    field :label, :string
    field :last_seen_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(sync_client, attrs) do
    sync_client
    |> cast(attrs, [:user_id, :client_id, :label, :last_seen_at])
    |> validate_required([:user_id, :client_id, :label, :last_seen_at])
    |> validate_length(:client_id, max: 128)
    |> validate_length(:label, max: 128)
    |> unique_constraint(:client_id, name: :sync_clients_user_id_client_id_index)
  end
end
