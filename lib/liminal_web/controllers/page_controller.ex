defmodule LiminalWeb.PageController do
  use LiminalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
