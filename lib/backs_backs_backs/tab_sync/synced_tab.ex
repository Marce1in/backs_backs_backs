defmodule BacksBacksBacks.TabSync.SyncedTab do
  use Ecto.Schema

  import Ecto.Changeset

  schema "synced_tabs" do
    field :tab_key, :string
    field :fingerprint, :string
    field :url, :string
    field :title, :string
    field :position, :integer
    field :group_key, :string
    field :last_seen_client_id, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(synced_tab, attrs) do
    synced_tab
    |> cast(attrs, [
      :tab_key,
      :fingerprint,
      :url,
      :title,
      :position,
      :group_key,
      :last_seen_client_id
    ])
    |> validate_required([:tab_key, :fingerprint, :url, :title, :position, :last_seen_client_id])
    |> validate_length(:tab_key, max: 128)
    |> validate_length(:fingerprint, max: 96)
    |> validate_length(:title, max: 512)
    |> validate_length(:group_key, max: 96)
    |> validate_length(:last_seen_client_id, max: 128)
    |> unique_constraint(:tab_key)
  end
end
