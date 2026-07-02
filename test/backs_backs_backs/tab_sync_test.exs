defmodule BacksBacksBacks.TabSyncTest do
  use BacksBacksBacks.DataCase, async: true

  alias BacksBacksBacks.TabSync
  alias BacksBacksBacks.Accounts.User
  alias BacksBacksBacks.TabSync.{SyncedTab, SyncedTabGroup}

  setup do
    {:ok, user: insert_user()}
  end

  describe "normalize_url/1" do
    test "keeps path query and hash while stripping credentials" do
      assert {:ok, url} =
               TabSync.normalize_url("https://user:pass@Example.com/docs?token=abc#part")

      assert url == "https://example.com/docs?token=abc#part"
    end

    test "rejects non-web urls" do
      assert :error = TabSync.normalize_url("chrome://extensions")
      assert :error = TabSync.normalize_url("file:///tmp/report.html")
      assert :error = TabSync.normalize_url("not a url")
    end
  end

  describe "upsert/2" do
    test "persists normalized tabs and groups", %{user: user} do
      assert {:ok, changes} =
               TabSync.upsert(user.id, "client-a", %{
                 "groups" => [
                   %{
                     "groupKey" => "research",
                     "title" => "Research",
                     "color" => "green",
                     "position" => 2
                   }
                 ],
                 "tabs" => [
                   %{
                     "url" => "https://user:pass@example.com/docs?q=1#section",
                     "title" => " Docs ",
                     "position" => 3,
                     "groupKey" => "research"
                   }
                 ]
               })

      assert [%{"url" => "https://example.com/docs?q=1#section"}] = changes["tabs"]
      assert [%{"groupKey" => "research", "color" => "green"}] = changes["groups"]

      assert [%SyncedTab{url: "https://example.com/docs?q=1#section", title: "Docs"}] =
               Repo.all(SyncedTab)

      assert [%SyncedTabGroup{group_key: "research", title: "Research", color: "green"}] =
               Repo.all(SyncedTabGroup)
    end

    test "ignores invalid tab urls", %{user: user} do
      assert {:ok, %{"tabs" => [%{"url" => "https://example.com"}]}} =
               TabSync.upsert(user.id, "client-a", %{
                 "tabs" => [
                   %{"url" => "chrome://extensions", "title" => "Extensions"},
                   %{"url" => "https://example.com", "title" => "Example"}
                 ]
               })

      assert Repo.aggregate(SyncedTab, :count) == 1
    end

    test "is idempotent for the same normalized url", %{user: user} do
      assert {:ok, %{"tabs" => [%{"fingerprint" => fingerprint}]}} =
               TabSync.upsert(user.id, "client-a", %{
                 "tabs" => [%{"url" => "https://example.com/path", "title" => "First"}]
               })

      assert {:ok, %{"tabs" => [%{"fingerprint" => ^fingerprint}]}} =
               TabSync.upsert(user.id, "client-b", %{
                 "tabs" => [%{"url" => "https://example.com/path", "title" => "Second"}]
               })

      assert Repo.aggregate(SyncedTab, :count) == 1
      assert [%SyncedTab{title: "Second"}] = Repo.all(SyncedTab)
    end

    test "updates the same tab key when the url changes", %{user: user} do
      assert {:ok, %{"tabs" => [%{"tabKey" => "tab-1", "url" => "https://example.com/old"}]}} =
               TabSync.upsert(user.id, "client-a", %{
                 "tabs" => [
                   %{"tabKey" => "tab-1", "url" => "https://example.com/old", "title" => "Old"}
                 ]
               })

      assert {:ok, %{"tabs" => [%{"tabKey" => "tab-1", "url" => "https://example.com/new"}]}} =
               TabSync.upsert(user.id, "client-a", %{
                 "tabs" => [
                   %{"tabKey" => "tab-1", "url" => "https://example.com/new", "title" => "New"}
                 ]
               })

      assert Repo.aggregate(SyncedTab, :count) == 1

      assert [%SyncedTab{tab_key: "tab-1", url: "https://example.com/new", title: "New"}] =
               Repo.all(SyncedTab)
    end

    test "allows different tab keys with the same url fingerprint", %{user: user} do
      assert {:ok, _changes} =
               TabSync.upsert(user.id, "client-a", %{
                 "tabs" => [
                   %{"tabKey" => "tab-1", "url" => "https://example.com", "title" => "One"},
                   %{"tabKey" => "tab-2", "url" => "https://example.com", "title" => "Two"}
                 ]
               })

      assert Repo.aggregate(SyncedTab, :count) == 2
    end

    test "isolates tab state by user", %{user: user} do
      other_user = insert_user()

      assert {:ok, _changes} =
               TabSync.upsert(user.id, "client-a", %{
                 "tabs" => [%{"tabKey" => "shared", "url" => "https://a.example", "title" => "A"}]
               })

      assert {:ok, _changes} =
               TabSync.upsert(other_user.id, "client-b", %{
                 "tabs" => [%{"tabKey" => "shared", "url" => "https://b.example", "title" => "B"}]
               })

      assert [%{"url" => "https://a.example"}] = TabSync.state(user.id)["tabs"]
      assert [%{"url" => "https://b.example"}] = TabSync.state(other_user.id)["tabs"]
    end
  end

  describe "delete/2" do
    test "removes persisted tabs by fingerprint", %{user: user} do
      {:ok, %{"tabs" => [%{"fingerprint" => fingerprint}]}} =
        TabSync.upsert(user.id, "client-a", %{
          "tabs" => [%{"url" => "https://example.com", "title" => "Example"}]
        })

      assert {:ok, %{"deletedCount" => 1, "fingerprints" => [^fingerprint]}} =
               TabSync.delete(user.id, "client-b", %{"fingerprints" => [fingerprint]})

      assert Repo.aggregate(SyncedTab, :count) == 0
    end

    test "removes persisted tabs by tab key", %{user: user} do
      {:ok, _changes} =
        TabSync.upsert(user.id, "client-a", %{
          "tabs" => [%{"tabKey" => "tab-1", "url" => "https://example.com", "title" => "Example"}]
        })

      assert {:ok, %{"deletedCount" => 1, "tabKeys" => ["tab-1"]}} =
               TabSync.delete(user.id, "client-b", %{"tabKeys" => ["tab-1"]})

      assert Repo.aggregate(SyncedTab, :count) == 0
    end

    test "does not delete another user's matching tab key", %{user: user} do
      other_user = insert_user()

      {:ok, _changes} =
        TabSync.upsert(user.id, "client-a", %{
          "tabs" => [%{"tabKey" => "tab-1", "url" => "https://a.example", "title" => "A"}]
        })

      {:ok, _changes} =
        TabSync.upsert(other_user.id, "client-b", %{
          "tabs" => [%{"tabKey" => "tab-1", "url" => "https://b.example", "title" => "B"}]
        })

      assert {:ok, %{"deletedCount" => 1}} =
               TabSync.delete(user.id, "client-a", %{"tabKeys" => ["tab-1"]})

      assert [%{"url" => "https://b.example"}] = TabSync.state(other_user.id)["tabs"]
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
end
