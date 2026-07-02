defmodule BacksBacksBacksWeb.TabsChannelTest do
  use BacksBacksBacksWeb.ChannelCase

  alias BacksBacksBacks.Accounts.User
  alias BacksBacksBacks.Auth
  alias BacksBacksBacks.TabSync.SyncedTab
  alias BacksBacksBacks.TabOrganizer
  alias BacksBacksBacksWeb.UserSocket

  setup do
    previous_config = Application.get_env(:backs_backs_backs, TabOrganizer)

    Application.put_env(:backs_backs_backs, TabOrganizer,
      openrouter_client: __MODULE__.FakeOpenRouterClient,
      openrouter_api_key: "test-key",
      openrouter_model: "openrouter/test-model",
      scheduler_enabled: false,
      scheduler_interval_ms: 300_000
    )

    on_exit(fn ->
      Application.put_env(:backs_backs_backs, TabOrganizer, previous_config)
    end)
  end

  test "rejects socket connections without authentication" do
    assert :error = connect(UserSocket, %{"client_id" => "client-a", "client_label" => "Laptop"})
  end

  test "joins the authenticated user's tab topic" do
    user = insert_user()

    assert {:ok, socket} =
             connect(UserSocket, %{
               "auth_token" => socket_token(user),
               "client_id" => "client-a",
               "client_label" => "Laptop"
             })

    assert {:ok, reply, _socket} = subscribe_and_join(socket, "tabs:user:#{user.public_id}", %{})
    assert reply["clientId"] == "client-a"
    assert reply["clientLabel"] == "Laptop"
    assert reply["userId"] == user.public_id
    assert reply["tabs"] == []
    assert reply["groups"] == []

    assert_push "presence_state", %{}
  end

  test "rejects another user's tab topic" do
    user = insert_user()
    other_user = insert_user()

    {:ok, socket} =
      connect(UserSocket, %{"auth_token" => socket_token(user), "client_id" => "client-a"})

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(socket, "tabs:user:#{other_user.public_id}", %{})
  end

  test "upserts tabs, persists them, and broadcasts to other clients" do
    user = insert_user()

    {:ok, socket_a} =
      connect(UserSocket, %{"auth_token" => socket_token(user), "client_id" => "client-a"})

    {:ok, _reply, socket_a} = subscribe_and_join(socket_a, "tabs:user:#{user.public_id}", %{})
    assert_push "presence_state", %{}

    {:ok, socket_b} =
      connect(UserSocket, %{"auth_token" => socket_token(user), "client_id" => "client-b"})

    {:ok, _reply, _socket_b} = subscribe_and_join(socket_b, "tabs:user:#{user.public_id}", %{})
    assert_push "presence_state", %{}

    ref =
      push(socket_a, "tabs:upsert", %{
        "groups" => [
          %{"groupKey" => "work", "title" => "Work", "color" => "blue", "position" => 0}
        ],
        "tabs" => [
          %{
            "url" => "https://user:pass@example.com/path?x=1",
            "title" => "Example",
            "position" => 0,
            "groupKey" => "work"
          }
        ]
      })

    assert_reply ref, :ok, %{"tabs" => [%{"url" => "https://example.com/path?x=1"}]}

    assert_broadcast "tabs:upserted", %{
      "originClientId" => "client-a",
      "tabs" => [%{"url" => "https://example.com/path?x=1"}]
    }

    assert Repo.aggregate(SyncedTab, :count) == 1
  end

  test "deletes tabs and broadcasts deleted fingerprints" do
    user = insert_user()

    {:ok, socket_a} =
      connect(UserSocket, %{"auth_token" => socket_token(user), "client_id" => "client-a"})

    {:ok, _reply, socket_a} = subscribe_and_join(socket_a, "tabs:user:#{user.public_id}", %{})
    assert_push "presence_state", %{}

    upsert_ref =
      push(socket_a, "tabs:upsert", %{
        "tabs" => [%{"url" => "https://example.com", "title" => "Example"}]
      })

    assert_reply upsert_ref, :ok, %{"tabs" => [%{"fingerprint" => fingerprint}]}

    delete_ref = push(socket_a, "tabs:delete", %{"fingerprints" => [fingerprint]})

    assert_reply delete_ref, :ok, %{
      "originClientId" => "client-a",
      "fingerprints" => [^fingerprint],
      "deletedCount" => 1
    }

    assert Repo.aggregate(SyncedTab, :count) == 0
  end

  test "organizes tabs through the backend and broadcasts server state" do
    user = insert_user()

    {:ok, socket_a} =
      connect(UserSocket, %{"auth_token" => socket_token(user), "client_id" => "client-a"})

    {:ok, _reply, socket_a} = subscribe_and_join(socket_a, "tabs:user:#{user.public_id}", %{})
    assert_push "presence_state", %{}

    upsert_ref =
      push(socket_a, "tabs:upsert", %{
        "tabs" => [
          %{"tabKey" => "tab-1", "url" => "https://example.com/a", "title" => "A"},
          %{"tabKey" => "tab-2", "url" => "https://example.com/b", "title" => "B"}
        ]
      })

    assert_reply upsert_ref, :ok, %{"tabs" => [_tab_a, _tab_b]}

    organize_ref = push(socket_a, "tabs:organize_now", %{})

    assert_reply organize_ref, :ok, %{
      "appliedGroups" => 1,
      "groupedTabs" => 2,
      "model" => "openrouter/test-model"
    }

    assert_broadcast "tabs:upserted", %{
      "originClientId" => "server",
      "groups" => [%{"title" => "Work"}]
    }
  end

  defmodule FakeOpenRouterClient do
    def request_plan(_tabs) do
      {:ok,
       %{
         "groups" => [
           %{"name" => "Work", "color" => "blue", "tabKeys" => ["tab-1", "tab-2"]}
         ],
         "ungroupedTabKeys" => []
       }}
    end
  end

  defp insert_user do
    unique = System.unique_integer([:positive])

    %User{}
    |> User.github_changeset(%{
      public_id: "gh_test_#{unique}",
      github_id: to_string(unique),
      login: "user#{unique}",
      last_login_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    })
    |> Repo.insert!()
  end

  defp socket_token(user), do: Auth.socket_token_for_user(user).token
end
