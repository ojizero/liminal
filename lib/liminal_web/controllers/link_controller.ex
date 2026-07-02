defmodule LiminalWeb.LinkController do
  use LiminalWeb, :controller

  alias Liminal.Links

  def random(conn, _params) do
    scope = conn.assigns.current_scope

    case Links.random_link(scope) do
      {:error, :no_links} ->
        conn
        |> put_flash(:error, "No links to open randomly")
        |> redirect(to: ~p"/")

      {:ok, link} ->
        if scope.user.auto_mark_viewed_on_open and is_nil(link.viewed_at) do
          {:ok, _} = Links.mark_viewed(scope, link)
        end

        redirect(conn, external: link.url)
    end
  end
end
