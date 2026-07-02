defmodule BacksBacksBacksWeb.AuthController do
  use BacksBacksBacksWeb, :controller

  alias BacksBacksBacks.Auth

  def github_start(conn, %{"extensionRedirectUri" => extension_redirect_uri}) do
    case Auth.github_authorize_url(extension_redirect_uri) do
      {:ok, authorize_url} ->
        json(conn, %{authorizeUrl: authorize_url})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: to_string(reason)})
    end
  end

  def github_start(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_extension_redirect_uri"})
  end

  def github_callback(conn, %{"code" => code, "state" => state}) do
    case Auth.complete_github_callback(code, state) do
      {:ok, user, extension_redirect_uri, token_info} ->
        redirect(conn,
          external: Auth.callback_redirect_url(extension_redirect_uri, user, token_info)
        )

      {:error, reason} ->
        case Auth.callback_error_redirect_url(state, reason) do
          redirect_url when is_binary(redirect_url) ->
            redirect(conn, external: redirect_url)

          _ ->
            conn
            |> put_status(:bad_request)
            |> text("GitHub authentication failed.")
        end
    end
  end

  def github_callback(conn, params) do
    state = Map.get(params, "state", "")

    case Auth.callback_error_redirect_url(state, :github_denied) do
      redirect_url when is_binary(redirect_url) ->
        redirect(conn, external: redirect_url)

      _ ->
        conn
        |> put_status(:bad_request)
        |> text("GitHub authentication failed.")
    end
  end
end
