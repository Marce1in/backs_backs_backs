defmodule BacksBacksBacks.Auth do
  @moduledoc """
  GitHub OAuth and Phoenix socket-token helpers.
  """

  alias BacksBacksBacks.Accounts
  alias BacksBacksBacksWeb.Endpoint

  @authorize_url "https://github.com/login/oauth/authorize"
  @state_salt "github oauth state"
  @socket_token_salt "github socket token"
  @state_max_age 10 * 60
  @socket_token_max_age 30 * 24 * 60 * 60

  def github_authorize_url(extension_redirect_uri) when is_binary(extension_redirect_uri) do
    with :ok <- validate_extension_redirect_uri(extension_redirect_uri),
         {:ok, client_id} <- config_string(:github_client_id),
         {:ok, callback_url} <- config_string(:github_callback_url) do
      code_verifier = random_url_token(64)

      state =
        encrypted_state(%{
          extension_redirect_uri: extension_redirect_uri,
          code_verifier: code_verifier
        })

      query =
        %{
          client_id: client_id,
          redirect_uri: callback_url,
          state: state,
          code_challenge: code_challenge(code_verifier),
          code_challenge_method: "S256"
        }
        |> URI.encode_query()

      {:ok, "#{@authorize_url}?#{query}"}
    end
  end

  def github_authorize_url(_extension_redirect_uri), do: {:error, :invalid_redirect_uri}

  def complete_github_callback(code, state) when is_binary(code) and is_binary(state) do
    with {:ok, %{extension_redirect_uri: extension_redirect_uri, code_verifier: code_verifier}} <-
           decrypt_state(state),
         :ok <- validate_extension_redirect_uri(extension_redirect_uri),
         {:ok, client_id} <- config_string(:github_client_id),
         {:ok, client_secret} <- config_string(:github_client_secret),
         {:ok, callback_url} <- config_string(:github_callback_url),
         {:ok, access_token} <-
           github_client().exchange_code(%{
             client_id: client_id,
             client_secret: client_secret,
             code: code,
             redirect_uri: callback_url,
             code_verifier: code_verifier
           }),
         {:ok, github_user} <- github_client().fetch_user(access_token),
         %Accounts.User{} = user <- Accounts.upsert_github_user(github_user) do
      {:ok, user, extension_redirect_uri, socket_token_for_user(user)}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :user_upsert_failed}
      other -> {:error, other}
    end
  end

  def complete_github_callback(_code, _state), do: {:error, :invalid_callback}

  def verify_socket_token(token) when is_binary(token) do
    case Phoenix.Token.verify(Endpoint, @socket_token_salt, token, max_age: @socket_token_max_age) do
      {:ok, public_id} when is_binary(public_id) ->
        case Accounts.get_user_by_public_id(public_id) do
          %Accounts.User{} = user -> {:ok, user}
          nil -> {:error, :user_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify_socket_token(_token), do: {:error, :missing_token}

  def socket_token_for_user(%Accounts.User{} = user) do
    expires_at = DateTime.utc_now() |> DateTime.add(@socket_token_max_age, :second)

    %{
      token: Phoenix.Token.sign(Endpoint, @socket_token_salt, user.public_id),
      expires_at: DateTime.to_iso8601(expires_at)
    }
  end

  def callback_redirect_url(extension_redirect_uri, %Accounts.User{} = user, token_info) do
    fragment =
      %{
        token: token_info.token,
        expiresAt: token_info.expires_at,
        userId: user.public_id,
        login: user.login,
        name: user.name || "",
        avatarUrl: user.avatar_url || ""
      }
      |> URI.encode_query()

    "#{extension_redirect_uri}##{fragment}"
  end

  def callback_error_redirect_url(state, reason) do
    with {:ok, %{extension_redirect_uri: extension_redirect_uri}} <- decrypt_state(state),
         :ok <- validate_extension_redirect_uri(extension_redirect_uri) do
      "#{extension_redirect_uri}##{URI.encode_query(%{error: to_string(reason)})}"
    end
  end

  defp encrypted_state(payload) do
    Phoenix.Token.encrypt(Endpoint, @state_salt, payload)
  end

  defp decrypt_state(state) do
    Phoenix.Token.decrypt(Endpoint, @state_salt, state, max_age: @state_max_age)
  end

  defp config_string(key) do
    case Application.get_env(:backs_backs_backs, __MODULE__, []) |> Keyword.get(key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_config, key}}
    end
  end

  defp github_client do
    Application.get_env(:backs_backs_backs, __MODULE__, [])
    |> Keyword.get(:github_client, BacksBacksBacks.Auth.GitHubClient)
  end

  defp validate_extension_redirect_uri(uri) do
    allowed =
      Application.get_env(:backs_backs_backs, __MODULE__, [])
      |> Keyword.get(:extension_redirect_uris, [])

    if uri in allowed, do: :ok, else: {:error, :unallowed_redirect_uri}
  end

  defp code_challenge(code_verifier) do
    :crypto.hash(:sha256, code_verifier)
    |> Base.url_encode64(padding: false)
  end

  defp random_url_token(bytes) do
    bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
