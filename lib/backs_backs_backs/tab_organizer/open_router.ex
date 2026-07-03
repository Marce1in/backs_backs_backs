defmodule BacksBacksBacks.TabOrganizer.OpenRouter do
  @moduledoc """
  OpenRouter chat-completions client for server-side tab organization.
  """

  @chat_completions_url "https://openrouter.ai/api/v1/chat/completions"
  @title "Tabs Tabs Tabs"
  @colors ~w(grey blue red yellow green pink purple cyan orange)
  # OpenRouter pode levar bem mais que o receive_timeout padrão do Req (15s)
  # para responder um agrupamento com structured output. Fica abaixo dos 60s
  # de timeout do push no cliente, para que o erro chegue como reply e não
  # como timeout silencioso na extensão.
  @receive_timeout_ms 55_000

  def request_plan(tabs, existing_groups) when is_list(tabs) and is_list(existing_groups) do
    with {:ok, api_key} <- api_key() do
      body = request_body(model(), tabs, existing_groups)

      case Req.post(@chat_completions_url,
             headers: [
               {"authorization", "Bearer #{api_key}"},
               {"content-type", "application/json"},
               {"x-openrouter-title", @title}
             ],
             json: body,
             receive_timeout: @receive_timeout_ms
           ) do
        {:ok, %{status: status, body: payload}} when status in 200..299 ->
          parse_payload(payload)

        {:ok, %{status: status, body: payload}} ->
          {:error, openrouter_error(payload, status)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def request_body(model, tabs, existing_groups \\ []) do
    %{
      model: model,
      stream: false,
      temperature: 0.2,
      max_tokens: 1800,
      provider: %{
        require_parameters: true
      },
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "tab_organization",
          strict: true,
          schema: response_schema()
        }
      },
      messages: [
        %{
          role: "system",
          content:
            [
              "You organize browser tabs into Chrome tab groups.",
              "Return only JSON that matches the provided schema.",
              "Every tabKey from the input must appear exactly once: either inside one group's tabKeys or in ungroupedTabKeys. Never invent tabKeys.",
              "The input includes the user's current groups (existingGroups) and each tab's currentGroupId.",
              "Strongly prefer the existing organization: keep tabs in their current groups and assign new or ungrouped tabs into a fitting existing group.",
              "To reuse an existing group, set existingGroupId to its id and keep its name and color unchanged.",
              "Only create a new group (existingGroupId = null), rename, merge or split groups when the current organization is clearly wrong or a significantly better one exists. Small improvements are not worth reshuffling the user's groups.",
              "Group names: at most 2 words, under 32 characters, in the dominant language of the tabs.",
              "Avoid single-tab groups unless the tab is clearly distinct from everything else."
            ]
            |> Enum.join(" ")
        },
        %{
          role: "user",
          content: Jason.encode!(%{tabs: tabs, existingGroups: existing_groups})
        }
      ]
    }
  end

  def response_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        groups: %{
          type: "array",
          maxItems: 12,
          items: %{
            type: "object",
            additionalProperties: false,
            properties: %{
              existingGroupId: %{
                type: ["string", "null"],
                description:
                  "Id of the existing group being reused (from existingGroups), or null when creating a new group. Prefer reusing existing groups."
              },
              name: %{
                type: "string",
                description: "Short tab group name: at most 2 words and under 32 characters."
              },
              color: %{
                type: "string",
                enum: @colors,
                description: "Chrome tab group color."
              },
              tabKeys: %{
                type: "array",
                minItems: 1,
                items: %{
                  type: "string",
                  description: "A tabKey from the provided tab list."
                }
              }
            },
            required: ["existingGroupId", "name", "color", "tabKeys"]
          }
        },
        ungroupedTabKeys: %{
          type: "array",
          items: %{
            type: "string",
            description: "tabKeys that should stay outside of any group."
          }
        }
      },
      required: ["groups", "ungroupedTabKeys"]
    }
  end

  defp parse_payload(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    parse_model_content(content)
  end

  defp parse_payload(_payload), do: {:error, :missing_openrouter_content}

  defp parse_model_content(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :invalid_openrouter_json}
    end
  end

  defp parse_model_content(content) when is_map(content), do: {:ok, content}

  defp parse_model_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"text" => text} when is_binary(text) -> text
      %{text: text} when is_binary(text) -> text
      _ -> ""
    end)
    |> Enum.join("")
    |> parse_model_content()
  end

  defp parse_model_content(_content), do: {:error, :missing_openrouter_content}

  defp openrouter_error(%{"error" => %{"message" => message}}, _status) when is_binary(message) do
    message
  end

  defp openrouter_error(_payload, status), do: "openrouter_status_#{status}"

  defp api_key do
    case config() |> Keyword.get(:openrouter_api_key, "") do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_openrouter_api_key}
    end
  end

  defp model do
    config() |> Keyword.get(:openrouter_model, "openrouter/owl-alpha")
  end

  defp config do
    Application.get_env(:backs_backs_backs, BacksBacksBacks.TabOrganizer, [])
  end
end
