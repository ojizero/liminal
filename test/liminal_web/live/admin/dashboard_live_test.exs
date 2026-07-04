defmodule LiminalWeb.Admin.DashboardLiveTest do
  use LiminalWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Liminal.Links.MassReindexer

  setup do
    reindexer_pid = start_supervised!({MassReindexer, []})
    Ecto.Adapters.SQL.Sandbox.allow(Liminal.Repo, self(), reindexer_pid)
    {:ok, reindexer_pid: reindexer_pid}
  end

  describe "unauthenticated" do
    test "redirects from /admin to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin")
      assert {:redirect, %{to: to}} = redirect
      assert to =~ ~p"/users/register"
    end
  end

  describe "non-admin user" do
    setup :register_and_log_in_user

    test "redirects from /admin to home", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin")
      assert {:redirect, %{to: to}} = redirect
      assert to == ~p"/"
    end
  end

  describe "admin user" do
    setup :register_and_log_in_admin

    test "renders dashboard with instance stats", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "header", "Admin Dashboard")
      assert has_element?(view, "#admin-stats")
      assert has_element?(view, "#stat-total-links")
      assert has_element?(view, "#stat-total-users")
    end

    test "shows user stats on links page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#user-stats")
      assert has_element?(view, "#stat-total-links")
      refute has_element?(view, "#stat-total-users")
    end

    test "starts a failed reindex job", %{conn: conn, scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, link} = Liminal.Links.create_link(scope, %{url: "https://fail.example.com"}, [tag.id])

      now = DateTime.utc_now(:second)

      Liminal.Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [index_attempt_count: 1, index_last_attempted_at: now]
      )

      {:ok, view, _html} = live(conn, ~p"/admin")

      view |> element("#reindex-failed-btn") |> render_click()

      assert has_element?(view, "#reindex-status", "Running")
      assert has_element?(view, "#reindex-progress")
    end

    test "navigates to user management", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      {:ok, users_view, _html} =
        view
        |> element("a", "Manage Users")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users")

      assert has_element?(users_view, "header", "Users")
    end
  end
end
