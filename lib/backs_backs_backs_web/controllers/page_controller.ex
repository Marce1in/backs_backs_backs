defmodule BacksBacksBacksWeb.PageController do
  use BacksBacksBacksWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
