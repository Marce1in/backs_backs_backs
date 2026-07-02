defmodule BacksBacksBacks.Accounts do
  @moduledoc """
  User persistence for GitHub-backed accounts.
  """

  import Ecto.Query

  alias BacksBacksBacks.Accounts.User
  alias BacksBacksBacks.Repo

  def get_user_by_public_id(public_id) when is_binary(public_id) do
    Repo.get_by(User, public_id: public_id)
  end

  def get_user(id) when is_integer(id), do: Repo.get(User, id)

  def list_users do
    User
    |> order_by([user], asc: user.id)
    |> Repo.all()
  end

  def upsert_github_user(%{"id" => github_id, "login" => login} = github_user) do
    github_id = to_string(github_id)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    public_id = github_user |> Map.get("node_id") |> public_id_for(github_id)

    attrs = %{
      public_id: public_id,
      github_id: github_id,
      login: normalize_text(login, "github-user", 128),
      name: normalize_optional_text(Map.get(github_user, "name"), 256),
      avatar_url: normalize_optional_text(Map.get(github_user, "avatar_url"), 1024),
      last_login_at: now
    }

    %User{}
    |> User.github_changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          login: attrs.login,
          name: attrs.name,
          avatar_url: attrs.avatar_url,
          last_login_at: attrs.last_login_at,
          updated_at: now
        ]
      ],
      conflict_target: :github_id
    )

    Repo.one(from user in User, where: user.github_id == ^github_id)
  end

  def upsert_github_user(_github_user), do: {:error, :invalid_github_user}

  def update_tab_organization_signature(%User{} = user, signature) when is_binary(signature) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    user
    |> User.organization_signature_changeset(%{
      last_tab_organization_signature: signature,
      last_tab_organization_at: now
    })
    |> Repo.update()
  end

  defp public_id_for(node_id, _github_id) when is_binary(node_id) and node_id != "" do
    "gh_#{Base.url_encode64(node_id, padding: false)}" |> String.slice(0, 64)
  end

  defp public_id_for(_node_id, github_id) do
    "gh_#{Base.url_encode64(github_id, padding: false)}"
  end

  defp normalize_text(value, fallback, max_length) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, max_length)
    |> case do
      "" -> fallback
      normalized -> normalized
    end
  end

  defp normalize_text(_value, fallback, _max_length), do: fallback

  defp normalize_optional_text(value, max_length) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, max_length)
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_text(_value, _max_length), do: nil
end
