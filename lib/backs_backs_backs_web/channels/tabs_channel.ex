defmodule BacksBacksBacksWeb.TabsChannel do
  use BacksBacksBacksWeb, :channel

  alias BacksBacksBacks.TabSync
  alias BacksBacksBacks.TabOrganizer
  alias BacksBacksBacksWeb.Presence

  @impl true
  def join("tabs:user:" <> public_id, _payload, socket) do
    if public_id == socket.assigns.user_public_id do
      join_user_channel(socket)
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp join_user_channel(socket) do
    user_id = socket.assigns.user_id
    client_id = socket.assigns.client_id
    client_label = socket.assigns.client_label

    with {:ok, _client} <- TabSync.upsert_client(user_id, client_id, client_label) do
      send(self(), :after_join)

      {:ok,
       TabSync.state(user_id)
       |> Map.put("clientId", client_id)
       |> Map.put("clientLabel", client_label)
       |> Map.put("userId", socket.assigns.user_public_id)
       |> Map.put("login", socket.assigns.user_login), socket}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, socket.assigns.client_id, %{
        label: socket.assigns.client_label,
        online_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in("tabs:request_state", _payload, socket) do
    {:reply, {:ok, TabSync.state(socket.assigns.user_id)}, socket}
  end

  def handle_in("tabs:upsert", payload, socket) do
    user_id = socket.assigns.user_id
    client_id = socket.assigns.client_id

    case TabSync.upsert(user_id, client_id, payload) do
      {:ok, changes} ->
        broadcast_from!(socket, "tabs:upserted", Map.put(changes, "originClientId", client_id))
        {:reply, {:ok, Map.put(changes, "state", TabSync.state(user_id))}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  def handle_in("tabs:delete", payload, socket) do
    user_id = socket.assigns.user_id
    client_id = socket.assigns.client_id

    case TabSync.delete(user_id, client_id, payload) do
      {:ok, changes} ->
        broadcast_from!(socket, "tabs:deleted", changes)
        {:reply, {:ok, changes}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  def handle_in("tabs:organize_now", _payload, socket) do
    case TabOrganizer.organize_user(socket.assigns.user_id, force: true, broadcast: true) do
      {:ok, result} ->
        {:reply, {:ok, result}, socket}

      {:skip, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => error_reason(reason)}}, socket}
    end
  end

  defp error_reason(reason) when is_binary(reason), do: reason
  defp error_reason(reason) when is_atom(reason), do: to_string(reason)
  defp error_reason(reason) when is_exception(reason), do: Exception.message(reason)
  defp error_reason(reason), do: inspect(reason)
end
