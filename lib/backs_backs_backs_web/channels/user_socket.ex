defmodule BacksBacksBacksWeb.UserSocket do
  use Phoenix.Socket

  alias BacksBacksBacks.Auth

  channel "tabs:user:*", BacksBacksBacksWeb.TabsChannel

  @impl true
  def connect(params, socket, _connect_info) do
    with {:ok, user} <- Auth.verify_socket_token(params["auth_token"]) do
      client_id = clean_param(params["client_id"], Ecto.UUID.generate(), 128)
      client_label = clean_param(params["client_label"], "Anonymous", 128)

      socket =
        socket
        |> assign(:user_id, user.id)
        |> assign(:user_public_id, user.public_id)
        |> assign(:user_login, user.login)
        |> assign(:client_id, client_id)
        |> assign(:client_label, client_label)

      {:ok, socket}
    else
      _ -> :error
    end
  end

  @impl true
  def id(socket), do: "tab_sync:#{socket.assigns.user_public_id}:#{socket.assigns.client_id}"

  defp clean_param(value, fallback, max_length) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, max_length)
    |> case do
      "" -> fallback
      normalized -> normalized
    end
  end

  defp clean_param(_value, fallback, _max_length), do: fallback
end
