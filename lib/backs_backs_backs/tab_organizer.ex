defmodule BacksBacksBacks.TabOrganizer do
  @moduledoc """
  Server-side AI organization for synced browser tabs.
  """

  alias BacksBacksBacks.Accounts
  alias BacksBacksBacks.Accounts.User
  alias BacksBacksBacks.TabSync
  alias BacksBacksBacksWeb.Endpoint

  @colors ~w(grey blue red yellow green pink purple cyan orange)
  @default_group_color "grey"
  @default_group_title "Group"
  @server_origin_client_id "server"

  def organize_user(user_or_id, opts \\ [])

  def organize_user(user_id, opts) when is_integer(user_id) do
    case Accounts.get_user(user_id) do
      %User{} = user -> organize_user(user, opts)
      nil -> {:error, :user_not_found}
    end
  end

  def organize_user(%User{} = user, opts) do
    force? = Keyword.get(opts, :force, false)
    broadcast? = Keyword.get(opts, :broadcast, true)
    state = TabSync.state(user.id)
    tabs = read_tabs(state)

    with :ok <- ensure_enough_tabs(tabs),
         signature <- input_signature(tabs),
         :ok <- ensure_changed(user, signature, force?),
         {:ok, plan} <- openrouter_client().request_plan(Enum.map(tabs, &ai_tab_payload/1)),
         {:ok, normalized_plan} <- normalize_plan(plan, tabs),
         {:ok, next_state} <- TabSync.apply_organization(user.id, normalized_plan.groups),
         {:ok, _user} <- Accounts.update_tab_organization_signature(user, signature) do
      if broadcast?, do: broadcast_state(user, next_state)

      {:ok,
       result_payload(
         tabs,
         normalized_plan,
         next_state,
         model()
       )}
    end
  end

  def normalize_plan(input, tabs) when is_list(tabs) do
    with raw_groups when is_list(raw_groups) <- payload_value(input, "groups", :groups) do
      valid_tab_keys = MapSet.new(Enum.map(tabs, & &1["tabKey"]))

      {groups, grouped_tab_keys, warnings} =
        raw_groups
        |> Enum.take(12)
        |> Enum.with_index()
        |> Enum.reduce({[], MapSet.new(), []}, fn {group, index}, acc ->
          normalize_group(group, index, valid_tab_keys, acc)
        end)

      ungrouped_tab_keys =
        input
        |> payload_list("ungroupedTabKeys", :ungrouped_tab_keys)
        |> normalize_tab_keys(valid_tab_keys, grouped_tab_keys)

      missing_tab_keys =
        valid_tab_keys
        |> MapSet.difference(grouped_tab_keys)
        |> MapSet.difference(MapSet.new(ungrouped_tab_keys))
        |> MapSet.to_list()

      groups = Enum.reverse(groups)
      warnings = Enum.reverse(warnings)

      if groups == [] do
        {:error, :no_usable_groups}
      else
        {:ok,
         %{
           groups: groups,
           grouped_tab_keys: MapSet.to_list(grouped_tab_keys),
           ungrouped_tab_keys: ungrouped_tab_keys ++ missing_tab_keys,
           warnings: warnings
         }}
      end
    else
      _ -> {:error, :invalid_ai_response}
    end
  end

  def input_signature(tabs) when is_list(tabs) do
    tabs
    |> Enum.map(fn tab ->
      %{
        "tabKey" => tab["tabKey"],
        "title" => tab["title"],
        "url" => tab["url"],
        "position" => tab["position"]
      }
    end)
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def ai_tab_payload(tab) do
    %{
      tabKey: tab["tabKey"],
      position: tab["position"],
      title: normalize_text(tab["title"], "Untitled tab", 512),
      domain: domain_label(tab["url"]),
      url: sanitize_url_for_ai(tab["url"])
    }
  end

  defp read_tabs(%{"tabs" => tabs}) when is_list(tabs), do: tabs
  defp read_tabs(_state), do: []

  defp ensure_enough_tabs(tabs) when length(tabs) >= 2, do: :ok
  defp ensure_enough_tabs(_tabs), do: {:skip, :not_enough_tabs}

  defp ensure_changed(%User{last_tab_organization_signature: signature}, signature, false)
       when is_binary(signature) do
    {:skip, :unchanged_tabs}
  end

  defp ensure_changed(_user, _signature, _force?), do: :ok

  defp normalize_group(group, index, valid_tab_keys, {groups, grouped_tab_keys, warnings})
       when is_map(group) do
    tab_keys =
      group
      |> payload_list("tabKeys", :tab_keys)
      |> normalize_tab_keys(valid_tab_keys, grouped_tab_keys)

    if tab_keys == [] do
      {groups, grouped_tab_keys,
       ["Grupo #{index + 1} ignorado porque não tinha abas válidas." | warnings]}
    else
      title = normalize_text(payload_value(group, "name", :name), @default_group_title, 32)
      color = normalize_color(payload_value(group, "color", :color))
      group_key = generated_group_key(title, color, tab_keys)

      normalized_group = %{
        "groupKey" => group_key,
        "title" => title,
        "color" => color,
        "position" => index,
        "tabKeys" => tab_keys
      }

      {[
         normalized_group | groups
       ], MapSet.union(grouped_tab_keys, MapSet.new(tab_keys)), warnings}
    end
  end

  defp normalize_group(_group, index, _valid_tab_keys, {groups, grouped_tab_keys, warnings}) do
    {groups, grouped_tab_keys, ["Grupo malformado ignorado no índice #{index}." | warnings]}
  end

  defp normalize_tab_keys(tab_keys, valid_tab_keys, grouped_tab_keys) do
    tab_keys
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.filter(
      &(MapSet.member?(valid_tab_keys, &1) and not MapSet.member?(grouped_tab_keys, &1))
    )
  end

  defp result_payload(tabs, normalized_plan, next_state, model) do
    grouped_tabs = length(normalized_plan.grouped_tab_keys)
    ungrouped_tabs = length(normalized_plan.ungrouped_tab_keys)

    %{
      "tabsAnalyzed" => length(tabs),
      "model" => model,
      "generatedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "warnings" => normalized_plan.warnings,
      "appliedGroups" => length(normalized_plan.groups),
      "groupedTabs" => grouped_tabs,
      "ungroupedTabs" => ungrouped_tabs,
      "skippedTabs" => max(0, length(tabs) - grouped_tabs - ungrouped_tabs),
      "state" => next_state
    }
  end

  defp broadcast_state(%User{} = user, state) do
    Endpoint.broadcast(
      "tabs:user:#{user.public_id}",
      "tabs:upserted",
      Map.put(state, "originClientId", @server_origin_client_id)
    )
  end

  defp sanitize_url_for_ai(raw_url) when is_binary(raw_url) do
    raw_url
    |> URI.parse()
    |> case do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        uri
        |> Map.merge(%{userinfo: nil, query: nil, fragment: nil, host: String.downcase(host)})
        |> URI.to_string()

      _ ->
        "unknown"
    end
  rescue
    URI.Error -> "unknown"
  end

  defp sanitize_url_for_ai(_raw_url), do: "unknown"

  defp domain_label(raw_url) when is_binary(raw_url) do
    case URI.parse(raw_url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        Regex.replace(~r/^www\./i, host, "")

      %URI{scheme: scheme} when is_binary(scheme) ->
        scheme

      _ ->
        "unknown"
    end
  rescue
    URI.Error -> "unknown"
  end

  defp domain_label(_raw_url), do: "unknown"

  defp generated_group_key(title, color, tab_keys) do
    fingerprint =
      :crypto.hash(:sha256, "#{title}:#{color}:#{Enum.join(tab_keys, ",")}")
      |> Base.encode16(case: :lower)

    "ai:#{fingerprint}"
  end

  defp normalize_color(color) when color in @colors, do: color
  defp normalize_color(_color), do: @default_group_color

  defp payload_list(payload, string_key, atom_key) do
    case payload_value(payload, string_key, atom_key) do
      value when is_list(value) -> value
      _ -> []
    end
  end

  defp payload_value(payload, string_key, atom_key) when is_map(payload) do
    Map.get(payload, string_key) || Map.get(payload, atom_key)
  end

  defp payload_value(_payload, _string_key, _atom_key), do: nil

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

  defp openrouter_client do
    config()
    |> Keyword.get(:openrouter_client, BacksBacksBacks.TabOrganizer.OpenRouter)
  end

  defp model do
    config()
    |> Keyword.get(:openrouter_model, "openrouter/owl-alpha")
  end

  defp config do
    Application.get_env(:backs_backs_backs, __MODULE__, [])
  end
end
