defmodule BacksBacksBacksWeb.TabsChannelTest do
  use BacksBacksBacksWeb.ChannelCase

  alias BacksBacksBacks.TabSync.SyncedTab
  alias BacksBacksBacksWeb.UserSocket

  test "joins tabs:global without authentication" do
    assert {:ok, socket} =
             connect(UserSocket, %{"client_id" => "client-a", "client_label" => "Laptop"})

    assert {:ok, reply, _socket} = subscribe_and_join(socket, "tabs:global", %{})
    assert reply["clientId"] == "client-a"
    assert reply["clientLabel"] == "Laptop"
    assert reply["tabs"] == []
    assert reply["groups"] == []

    assert_push "presence_state", %{}
  end

  test "upserts tabs, persists them, and broadcasts to other clients" do
    {:ok, socket_a} = connect(UserSocket, %{"client_id" => "client-a"})
    {:ok, _reply, socket_a} = subscribe_and_join(socket_a, "tabs:global", %{})
    assert_push "presence_state", %{}

    {:ok, socket_b} = connect(UserSocket, %{"client_id" => "client-b"})
    {:ok, _reply, _socket_b} = subscribe_and_join(socket_b, "tabs:global", %{})
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
    {:ok, socket_a} = connect(UserSocket, %{"client_id" => "client-a"})
    {:ok, _reply, socket_a} = subscribe_and_join(socket_a, "tabs:global", %{})
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
end
