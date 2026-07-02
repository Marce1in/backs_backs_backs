defmodule BacksBacksBacks.Auth.GitHubClient do
  @moduledoc false

  @user_agent "tabs-tabs-tabs"

  def exchange_code(params) do
    body = [
      client_id: params.client_id,
      client_secret: params.client_secret,
      code: params.code,
      redirect_uri: params.redirect_uri,
      code_verifier: params.code_verifier
    ]

    case Req.post("https://github.com/login/oauth/access_token",
           form: body,
           headers: [{"accept", "application/json"}, {"user-agent", @user_agent}]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} when is_binary(token) ->
        {:ok, token}

      {:ok, %{body: %{"error" => reason}}} ->
        {:error, reason}

      {:ok, %{status: status}} ->
        {:error, {:github_exchange_failed, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_user(access_token) when is_binary(access_token) do
    case Req.get("https://api.github.com/user",
           headers: [
             {"accept", "application/vnd.github+json"},
             {"authorization", "Bearer #{access_token}"},
             {"user-agent", @user_agent},
             {"x-github-api-version", "2022-11-28"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"id" => _id, "login" => _login} = user}} ->
        {:ok, user}

      {:ok, %{status: status}} ->
        {:error, {:github_user_failed, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
