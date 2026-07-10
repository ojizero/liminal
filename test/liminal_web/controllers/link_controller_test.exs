defmodule LiminalWeb.LinkControllerTest do
  use LiminalWeb.ConnCase, async: true

  import Liminal.AccountsFixtures
  import Liminal.LinksFixtures

  setup :register_and_log_in_user

  describe "GET /links/random" do
    test "redirects to a random saved link", %{conn: conn, scope: scope} do
      url = "https://random.example.com"
      _link = link_fixture(scope, %{url: url})

      conn = get(conn, ~p"/links/random")

      assert redirected_to(conn) == url
    end

    test "redirects home with an error when there are no links", %{conn: conn} do
      conn = get(conn, ~p"/links/random")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "No links to open randomly"
    end

    test "marks the link viewed and broadcasts when auto mark on open is enabled" do
      user = user_fixture()
      {:ok, user} = Liminal.Accounts.update_user_settings(user, %{auto_mark_viewed_on_open: true})
      scope = Liminal.Accounts.Scope.for_user(user)
      url = "https://random-mark.example.com"
      link = link_fixture(scope, %{url: url, title: "Random Mark"})

      Liminal.Links.subscribe_links(scope)

      conn = build_conn() |> log_in_user(user) |> get(~p"/links/random")

      assert redirected_to(conn) == url
      assert Liminal.Links.get_link!(scope, link.id).viewed_at

      assert_receive {:link_updated, broadcast_link}
      assert broadcast_link.id == link.id
      assert broadcast_link.viewed_at
    end

    test "does not mark the link viewed when auto mark on open is disabled", %{
      conn: conn,
      scope: scope
    } do
      url = "https://random-skip.example.com"
      link = link_fixture(scope, %{url: url})

      conn = get(conn, ~p"/links/random")

      assert redirected_to(conn) == url
      refute Liminal.Links.get_link!(scope, link.id).viewed_at
    end

    test "requires authentication", %{scope: scope} do
      url = "https://random-auth.example.com"
      _link = link_fixture(scope, %{url: url})

      conn = build_conn() |> get(~p"/links/random")

      assert redirected_to(conn) in [~p"/users/log-in", ~p"/users/register"]
    end
  end
end
