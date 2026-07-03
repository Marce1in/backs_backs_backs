defmodule BacksBacksBacks.TabOrganizerTest do
  use BacksBacksBacks.DataCase

  alias BacksBacksBacks.Accounts.User
  alias BacksBacksBacks.Repo
  alias BacksBacksBacks.TabOrganizer
  alias BacksBacksBacks.TabOrganizer.OpenRouter
  alias BacksBacksBacks.TabSync

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

    {:ok, user: insert_user()}
  end

  test "OpenRouter request body asks for tabKey-based groups and sends existing groups" do
    body =
      OpenRouter.request_body(
        "openrouter/test-model",
        [%{tabKey: "tab-1", title: "Docs", currentGroupId: "group-1"}],
        [%{id: "group-1", name: "Research", color: "blue"}]
      )

    assert body.model == "openrouter/test-model"
    assert [%{role: "system"}, %{role: "user", content: user_content}] = body.messages

    assert %{
             "tabs" => [%{"tabKey" => "tab-1", "currentGroupId" => "group-1"}],
             "existingGroups" => [%{"id" => "group-1", "name" => "Research"}]
           } = Jason.decode!(user_content)

    group_properties = body.response_format.json_schema.schema.properties.groups.items.properties
    assert group_properties.tabKeys
    assert group_properties.existingGroupId
  end

  test "organizes tabs with backend OpenRouter client and stores signature", %{user: user} do
    {:ok, _changes} =
      TabSync.upsert(user.id, "client-a", %{
        "tabs" => [
          %{
            "tabKey" => "tab-1",
            "url" => "https://user:pass@example.com/docs?token=abc#part",
            "title" => "Docs"
          },
          %{
            "tabKey" => "tab-2",
            "url" => "https://news.example/top",
            "title" => "News"
          }
        ]
      })

    assert {:ok,
            %{
              "appliedGroups" => 1,
              "groupedTabs" => 2,
              "model" => "openrouter/test-model",
              "state" => %{"groups" => [%{"title" => "Research"}], "tabs" => tabs}
            }} = TabOrganizer.organize_user(user, force: true, broadcast: false)

    assert Enum.all?(tabs, &(&1["groupKey"] != nil))

    user = Repo.get!(User, user.id)
    assert is_binary(user.last_tab_organization_signature)
    assert user.last_tab_organization_at

    assert {:skip, :unchanged_tabs} = TabOrganizer.organize_user(user, broadcast: false)
  end

  test "skips users with fewer than two tabs", %{user: user} do
    {:ok, _changes} =
      TabSync.upsert(user.id, "client-a", %{
        "tabs" => [%{"tabKey" => "tab-1", "url" => "https://example.com", "title" => "Example"}]
      })

    assert {:skip, :not_enough_tabs} =
             TabOrganizer.organize_user(user, force: true, broadcast: false)
  end

  test "normalizes invalid AI response groups" do
    tabs = [
      %{"tabKey" => "tab-1", "title" => "One", "url" => "https://one.example", "position" => 0},
      %{"tabKey" => "tab-2", "title" => "Two", "url" => "https://two.example", "position" => 1}
    ]

    assert {:ok, plan} =
             TabOrganizer.normalize_plan(
               %{
                 "groups" => [
                   %{"name" => "Work", "color" => "blue", "tabKeys" => ["missing"]},
                   %{"name" => "Read", "color" => "bad", "tabKeys" => ["tab-1", "tab-1"]}
                 ],
                 "ungroupedTabKeys" => ["tab-2"]
               },
               tabs
             )

    assert [%{"color" => "grey", "tabKeys" => ["tab-1"]}] = plan.groups
    assert plan.ungrouped_tab_keys == ["tab-2"]
    assert plan.warnings == ["Grupo 1 ignorado porque não tinha abas válidas."]
  end

  test "keeps the original groupKey when the AI reuses an existing group" do
    tabs = [
      %{"tabKey" => "tab-1", "title" => "One", "url" => "https://one.example", "position" => 0},
      %{"tabKey" => "tab-2", "title" => "Two", "url" => "https://two.example", "position" => 1}
    ]

    existing_groups = [%{"groupKey" => "ai:abc123", "title" => "Research", "color" => "blue"}]

    assert {:ok, plan} =
             TabOrganizer.normalize_plan(
               %{
                 "groups" => [
                   %{
                     "existingGroupId" => "ai:abc123",
                     "name" => "Research",
                     "color" => "blue",
                     "tabKeys" => ["tab-1"]
                   },
                   %{
                     "existingGroupId" => "ai:unknown",
                     "name" => "News",
                     "color" => "red",
                     "tabKeys" => ["tab-2"]
                   }
                 ],
                 "ungroupedTabKeys" => []
               },
               tabs,
               existing_groups
             )

    assert [%{"groupKey" => "ai:abc123"}, %{"groupKey" => "ai:" <> generated}] = plan.groups
    refute generated == "unknown"
  end

  defmodule FakeOpenRouterClient do
    def request_plan(
          [
            %{tabKey: "tab-1", domain: "example.com", url: "https://example.com/docs"},
            %{tabKey: "tab-2", domain: "news.example", url: "https://news.example/top"}
          ],
          _existing_groups
        ) do
      {:ok,
       %{
         "groups" => [
           %{"name" => "Research", "color" => "blue", "tabKeys" => ["tab-1", "tab-2"]}
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
end
