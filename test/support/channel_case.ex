defmodule BacksBacksBacksWeb.ChannelCase do
  @moduledoc """
  Test case for Phoenix channels.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint BacksBacksBacksWeb.Endpoint

      alias BacksBacksBacks.Repo

      use BacksBacksBacksWeb, :verified_routes

      import Phoenix.ChannelTest
      import BacksBacksBacksWeb.ChannelCase
    end
  end

  setup tags do
    BacksBacksBacks.DataCase.setup_sandbox(tags)
    :ok
  end
end
