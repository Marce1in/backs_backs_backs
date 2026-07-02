defmodule BacksBacksBacksWeb.AuthControllerTest do
  use BacksBacksBacksWeb.ConnCase

  alias BacksBacksBacks.Accounts.User
  alias BacksBacksBacks.Repo

  @redirect_uri "https://extension.test/github"

  setup do
    previous_config = Application.get_env(:backs_backs_backs, BacksBacksBacks.Auth)

    Application.put_env(:backs_backs_backs, BacksBacksBacks.Auth,
      github_client: __MODULE__.FakeGitHubClient,
      github_client_id: "test-client-id",
      github_client_secret: "test-client-secret",
      github_callback_url: "http://localhost:4002/auth/github/callback",
      extension_redirect_uris: [@redirect_uri]
    )

    on_exit(fn ->
      Application.put_env(:backs_backs_backs, BacksBacksBacks.Auth, previous_config)
    end)
  end

  test "starts GitHub OAuth with an allowed extension redirect URI", %{conn: conn} do
    conn =
      post(conn, ~p"/api/auth/github/start", %{
        "extensionRedirectUri" => @redirect_uri
      })

    assert %{"authorizeUrl" => authorize_url} = json_response(conn, 200)
    uri = URI.parse(authorize_url)
    query = URI.decode_query(uri.query)

    assert uri.scheme == "https"
    assert uri.host == "github.com"
    assert query["client_id"] == "test-client-id"
    assert query["redirect_uri"] == "http://localhost:4002/auth/github/callback"
    assert query["code_challenge_method"] == "S256"
    assert is_binary(query["code_challenge"])
    assert is_binary(query["state"])
    refute Map.has_key?(query, "scope")
  end

  test "rejects unallowed extension redirect URIs", %{conn: conn} do
    conn =
      post(conn, ~p"/api/auth/github/start", %{
        "extensionRedirectUri" => "https://evil.test/github"
      })

    assert %{"error" => "unallowed_redirect_uri"} = json_response(conn, 400)
  end

  test "completes callback, upserts user, and redirects to the extension", %{conn: conn} do
    start_conn =
      post(conn, ~p"/api/auth/github/start", %{
        "extensionRedirectUri" => @redirect_uri
      })

    %{"authorizeUrl" => authorize_url} = json_response(start_conn, 200)

    state =
      authorize_url
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("state")

    conn =
      get(build_conn(), ~p"/auth/github/callback", %{"code" => "github-code", "state" => state})

    assert redirected_to(conn, 302) =~ @redirect_uri <> "#"
    redirect_uri = URI.parse(redirected_to(conn, 302))
    fragment = URI.decode_query(redirect_uri.fragment)

    assert fragment["token"]
    assert fragment["expiresAt"]
    assert fragment["login"] == "pablo"
    assert fragment["avatarUrl"] == "https://avatars.test/pablo.png"

    assert Repo.get_by(User, github_id: "123", login: "pablo")
  end

  defmodule FakeGitHubClient do
    def exchange_code(%{code: "github-code", code_verifier: code_verifier})
        when is_binary(code_verifier) and byte_size(code_verifier) > 20 do
      {:ok, "github-access-token"}
    end

    def fetch_user("github-access-token") do
      {:ok,
       %{
         "id" => 123,
         "node_id" => "U_123",
         "login" => "pablo",
         "name" => "Pablo",
         "avatar_url" => "https://avatars.test/pablo.png"
       }}
    end
  end
end
