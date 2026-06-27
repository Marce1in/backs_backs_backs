defmodule BacksBacksBacksWeb.TabsChannel do
  use BacksBacksBacksWeb, :channel

  alias BacksBacksBacks.TabSync
  alias BacksBacksBacksWeb.Presence

  @impl true
  def join("tabs:global", _payload, socket) do
    client_id = socket.assigns.client_id
    client_label = socket.assigns.client_label

    with {:ok, _client} <- TabSync.upsert_client(client_id, client_label) do
      send(self(), :after_join)

      {:ok,
       TabSync.state()
       |> Map.put("clientId", client_id)
       |> Map.put("clientLabel", client_label), socket}
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
    {:reply, {:ok, TabSync.state()}, socket}
  end

  def handle_in("tabs:upsert", payload, socket) do
    client_id = socket.assigns.client_id

    case TabSync.upsert(client_id, payload) do
      {:ok, changes} ->
        broadcast_from!(socket, "tabs:upserted", Map.put(changes, "originClientId", client_id))
        {:reply, {:ok, Map.put(changes, "state", TabSync.state())}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => to_string(reason)}}, socket}
    end
  end

  def handle_in("tabs:delete", payload, socket) do
    client_id = socket.assigns.client_id

    case TabSync.delete(client_id, payload) do
      {:ok, changes} ->
        broadcast_from!(socket, "tabs:deleted", changes)
        {:reply, {:ok, changes}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => to_string(reason)}}, socket}
    end
  end
end
