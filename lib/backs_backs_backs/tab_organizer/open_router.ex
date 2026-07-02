defmodule BacksBacksBacks.TabOrganizer.OpenRouter do
  @moduledoc """
  OpenRouter chat-completions client for server-side tab organization.
  """

  @chat_completions_url "https://openrouter.ai/api/v1/chat/completions"
  @title "Tabs Tabs Tabs"
  @colors ~w(grey blue red yellow green pink purple cyan orange)

  def request_plan(tabs) when is_list(tabs) do
    with {:ok, api_key} <- api_key() do
      body = request_body(model(), tabs)

      case Req.post(@chat_completions_url,
             headers: [
               {"authorization", "Bearer #{api_key}"},
               {"content-type", "application/json"},
               {"x-openrouter-title", @title}
             ],
             json: body
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

  def request_body(model, tabs) do
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
              "Você organiza abas do navegador em grupos úteis do Chrome.",
              "Retorne apenas JSON que corresponda ao schema fornecido.",
              "Cada tabKey deve aparecer exatamente uma vez, dentro de um grupo ou em ungroupedTabKeys.",
              "Não invente tabKeys. Use nomes de grupos com no máximo 2 palavras. Evite grupos com uma única aba, exceto quando a aba for claramente distinta."
            ]
            |> Enum.join(" ")
        },
        %{
          role: "user",
          content: Jason.encode!(%{tabs: tabs})
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
              name: %{
                type: "string",
                description:
                  "Nome curto do grupo de abas. Use no máximo 2 palavras e abaixo de 32 caracteres."
              },
              color: %{
                type: "string",
                enum: @colors,
                description: "Cor do grupo de abas do Chrome."
              },
              tabKeys: %{
                type: "array",
                minItems: 1,
                items: %{
                  type: "string",
                  description: "Uma tabKey da lista de abas fornecida."
                }
              }
            },
            required: ["name", "color", "tabKeys"]
          }
        },
        ungroupedTabKeys: %{
          type: "array",
          items: %{
            type: "string",
            description: "tabKeys que devem permanecer fora de grupos."
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
