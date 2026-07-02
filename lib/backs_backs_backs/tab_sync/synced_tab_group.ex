defmodule BacksBacksBacks.TabSync.SyncedTabGroup do
  use Ecto.Schema

  import Ecto.Changeset

  @colors ~w(grey blue red yellow green pink purple cyan orange)

  schema "synced_tab_groups" do
    field :user_id, :id
    field :group_key, :string
    field :title, :string
    field :color, :string
    field :position, :integer
    field :last_seen_client_id, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(synced_tab_group, attrs) do
    synced_tab_group
    |> cast(attrs, [:user_id, :group_key, :title, :color, :position, :last_seen_client_id])
    |> validate_required([:user_id, :group_key, :title, :color, :position, :last_seen_client_id])
    |> validate_inclusion(:color, @colors)
    |> validate_length(:group_key, max: 96)
    |> validate_length(:title, max: 32)
    |> validate_length(:last_seen_client_id, max: 128)
    |> unique_constraint(:group_key, name: :synced_tab_groups_user_id_group_key_index)
  end
end
