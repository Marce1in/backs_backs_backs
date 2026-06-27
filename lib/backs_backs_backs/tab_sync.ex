defmodule BacksBacksBacks.TabSync do
  @moduledoc """
  Persistence and normalization for the public tab-sync channel.
  """

  import Ecto.Query

  alias BacksBacksBacks.Repo
  alias BacksBacksBacks.TabSync.{SyncClient, SyncedTab, SyncedTabGroup}

  @colors ~w(grey blue red yellow green pink purple cyan orange)
  @default_group_color "grey"
  @default_group_title "Group"
  @default_tab_title "Untitled tab"

  def upsert_client(client_id, label) when is_binary(client_id) do
    now = now()
    label = normalize_text(label, "Anonymous", 128)

    attrs = %{
      client_id: normalize_text(client_id, client_id, 128),
      label: label,
      last_seen_at: now
    }

    %SyncClient{}
    |> SyncClient.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          label: attrs.label,
          last_seen_at: attrs.last_seen_at,
          updated_at: now
        ]
      ],
      conflict_target: :client_id
    )
  end

  def state do
    %{
      "tabs" =>
        SyncedTab
        |> order_by([tab], asc: tab.position, asc: tab.title)
        |> Repo.all()
        |> Enum.map(&tab_payload/1),
      "groups" =>
        SyncedTabGroup
        |> order_by([group], asc: group.position, asc: group.title)
        |> Repo.all()
        |> Enum.map(&group_payload/1)
    }
  end

  def upsert(origin_client_id, payload) when is_binary(origin_client_id) and is_map(payload) do
    groups = payload_list(payload, "groups", :groups)
    tabs = payload_list(payload, "tabs", :tabs)

    Repo.transaction(fn ->
      normalized_groups =
        groups
        |> Enum.map(&normalize_group(&1, origin_client_id))
        |> Enum.reject(&is_nil/1)

      Enum.each(normalized_groups, &upsert_group/1)

      normalized_tabs =
        tabs
        |> Enum.map(&normalize_tab(&1, origin_client_id))
        |> Enum.reject(&is_nil/1)

      Enum.each(normalized_tabs, &upsert_tab/1)

      %{
        "tabs" => Enum.map(normalized_tabs, &tab_payload/1),
        "groups" => Enum.map(normalized_groups, &group_payload/1)
      }
    end)
  end

  def upsert(_origin_client_id, _payload), do: {:error, :invalid_payload}

  def delete(origin_client_id, payload) when is_binary(origin_client_id) and is_map(payload) do
    tab_keys =
      (payload_list(payload, "tabKeys", :tabKeys) ++ payload_list(payload, "tab_keys", :tab_keys))
      |> normalize_key_list()

    fingerprints =
      payload
      |> payload_list("fingerprints", :fingerprints)
      |> normalize_key_list()

    {deleted_count, _} =
      delete_query(tab_keys, fingerprints)
      |> Repo.delete_all()

    {:ok,
     %{
       "originClientId" => origin_client_id,
       "tabKeys" => tab_keys,
       "fingerprints" => fingerprints,
       "deletedCount" => deleted_count
     }}
  end

  def delete(_origin_client_id, _payload), do: {:error, :invalid_payload}

  def normalize_url(raw_url) when is_binary(raw_url) do
    raw_url
    |> String.trim()
    |> URI.parse()
    |> normalize_uri()
  rescue
    URI.Error -> :error
  end

  def normalize_url(_raw_url), do: :error

  def fingerprint_for_url(url) when is_binary(url) do
    :crypto.hash(:sha256, url)
    |> Base.encode16(case: :lower)
  end

  defp normalize_uri(%URI{scheme: scheme, host: host} = uri)
       when is_binary(scheme) and is_binary(host) do
    scheme = String.downcase(scheme)

    if scheme in ["http", "https"] do
      normalized_uri = %{uri | scheme: scheme, host: String.downcase(host), userinfo: nil}
      {:ok, URI.to_string(normalized_uri)}
    else
      :error
    end
  end

  defp normalize_uri(_uri), do: :error

  defp normalize_group(payload, origin_client_id) when is_map(payload) do
    title = payload_value(payload, "title", :title) || payload_value(payload, "name", :name)
    title = normalize_text(title, @default_group_title, 32)
    color = normalize_color(payload_value(payload, "color", :color))
    position = normalize_position(payload_value(payload, "position", :position))

    group_key =
      payload_value(payload, "groupKey", :groupKey) ||
        payload_value(payload, "group_key", :group_key) ||
        generated_group_key(title, color)

    %SyncedTabGroup{
      group_key: normalize_text(group_key, generated_group_key(title, color), 96),
      title: title,
      color: color,
      position: position,
      last_seen_client_id: origin_client_id
    }
  end

  defp normalize_group(_payload, _origin_client_id), do: nil

  defp normalize_tab(payload, origin_client_id) when is_map(payload) do
    with raw_url when is_binary(raw_url) <- payload_value(payload, "url", :url),
         {:ok, url} <- normalize_url(raw_url) do
      title = normalize_text(payload_value(payload, "title", :title), @default_tab_title, 512)

      group_key =
        payload_value(payload, "groupKey", :groupKey) ||
          payload_value(payload, "group_key", :group_key)

      fingerprint = fingerprint_for_url(url)

      %SyncedTab{
        tab_key: normalize_text(read_tab_key(payload), fingerprint, 128),
        fingerprint: fingerprint,
        url: url,
        title: title,
        position: normalize_position(payload_value(payload, "position", :position)),
        group_key: normalize_optional_text(group_key, 96),
        last_seen_client_id: origin_client_id
      }
    else
      _ -> nil
    end
  end

  defp normalize_tab(_payload, _origin_client_id), do: nil

  defp upsert_group(%SyncedTabGroup{} = group) do
    now = now()
    attrs = Map.take(group, [:group_key, :title, :color, :position, :last_seen_client_id])

    %SyncedTabGroup{}
    |> SyncedTabGroup.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          title: group.title,
          color: group.color,
          position: group.position,
          last_seen_client_id: group.last_seen_client_id,
          updated_at: now
        ]
      ],
      conflict_target: :group_key
    )
  end

  defp upsert_tab(%SyncedTab{} = tab) do
    now = now()

    attrs =
      Map.take(tab, [
        :tab_key,
        :fingerprint,
        :url,
        :title,
        :position,
        :group_key,
        :last_seen_client_id
      ])

    %SyncedTab{}
    |> SyncedTab.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          url: tab.url,
          title: tab.title,
          position: tab.position,
          group_key: tab.group_key,
          last_seen_client_id: tab.last_seen_client_id,
          updated_at: now
        ]
      ],
      conflict_target: :tab_key
    )
  end

  defp tab_payload(%SyncedTab{} = tab) do
    %{
      "tabKey" => tab.tab_key,
      "fingerprint" => tab.fingerprint,
      "url" => tab.url,
      "title" => tab.title,
      "position" => tab.position,
      "groupKey" => tab.group_key
    }
  end

  defp group_payload(%SyncedTabGroup{} = group) do
    %{
      "groupKey" => group.group_key,
      "title" => group.title,
      "color" => group.color,
      "position" => group.position
    }
  end

  defp payload_list(payload, string_key, atom_key) do
    case payload_value(payload, string_key, atom_key) do
      value when is_list(value) -> value
      _ -> []
    end
  end

  defp payload_value(payload, string_key, atom_key) do
    Map.get(payload, string_key) || Map.get(payload, atom_key)
  end

  defp read_tab_key(payload) do
    payload_value(payload, "tabKey", :tabKey) || payload_value(payload, "tab_key", :tab_key)
  end

  defp normalize_key_list(keys) do
    keys
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp delete_query(tab_keys, _fingerprints) when tab_keys != [] do
    from(tab in SyncedTab, where: tab.tab_key in ^tab_keys)
  end

  defp delete_query(_tab_keys, fingerprints) do
    from(tab in SyncedTab, where: tab.fingerprint in ^fingerprints)
  end

  defp normalize_color(color) when color in @colors, do: color
  defp normalize_color(_color), do: @default_group_color

  defp normalize_position(position) when is_integer(position) and position >= 0, do: position
  defp normalize_position(_position), do: 0

  defp normalize_optional_text(value, max_length) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, max_length)
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_text(_value, _max_length), do: nil

  defp normalize_text(value, fallback, max_length) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, max_length)
    |> case do
      "" -> fallback
      normalized -> normalized
    end
  end

  defp normalize_text(_value, fallback, _max_length), do: fallback

  defp generated_group_key(title, color) do
    fingerprint_for_url("#{title}:#{color}")
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end
end
