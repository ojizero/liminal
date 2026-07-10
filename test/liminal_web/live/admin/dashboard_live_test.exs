defmodule LiminalWeb.Admin.DashboardLiveTest do
  use LiminalWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  setup :ensure_reindex_started!

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

      assert has_element?(view, "#admin-dashboard header", "Admin")
      assert has_element?(view, "#admin-stats")
      assert has_element?(view, "#stat-total-links")
      assert has_element?(view, "#stat-total-users")

      assert has_element?(
               view,
               "nav[aria-label='Admin sections'] a[aria-current='page']",
               "Overview"
             )
    end

    test "does not show user stats on links page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#user-stats")
      refute has_element?(view, "#stat-total-links")
    end

    test "shows user stats on settings page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      assert has_element?(view, "#user-stats")
      assert has_element?(view, "#stat-total-links")
      refute has_element?(view, "#stat-total-users")
    end

    test "starts a failed reindex job and disables new jobs while active", %{
      conn: conn,
      scope: scope
    } do
      tag = Liminal.LinksFixtures.tag_fixture(scope)

      {:ok, link1} =
        Liminal.Links.create_link(scope, %{url: "https://fail-one.example.com"}, [tag.id])

      {:ok, link2} =
        Liminal.Links.create_link(scope, %{url: "https://fail-two.example.com"}, [tag.id])

      now = DateTime.utc_now(:second)

      for link <- [link1, link2] do
        Liminal.Repo.update_all(
          from(l in Liminal.Links.Link, where: l.id == ^link.id),
          set: [index_attempt_count: 1, index_last_attempted_at: now]
        )
      end

      {:ok, view, _html} = live(conn, ~p"/admin")

      refute has_element?(view, "#admin-reindex-failed-btn[disabled]")
      refute has_element?(view, "#admin-reindex-all-btn[disabled]")

      view |> element("#admin-reindex-failed-btn") |> render_click()

      assert has_element?(view, "#admin-reindex-status", "Running")
      assert has_element?(view, "#admin-reindex-progress")
      assert has_element?(view, "#admin-reindex-failed-btn[disabled]")
      assert has_element?(view, "#admin-reindex-all-btn[disabled]")
    end

    test "blocks starting a second job while one is active", %{conn: conn, scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)

      {:ok, _} =
        Liminal.Links.create_link(scope, %{url: "https://busy-one.example.com"}, [tag.id])

      {:ok, _} =
        Liminal.Links.create_link(scope, %{url: "https://busy-two.example.com"}, [tag.id])

      {:ok, view, _html} = live(conn, ~p"/admin")

      view |> element("#admin-reindex-all-btn") |> render_click()
      assert has_element?(view, "#admin-reindex-status", "Running")
      assert has_element?(view, "#admin-reindex-failed-btn[disabled]")
      assert has_element?(view, "#admin-reindex-all-btn[disabled]")
    end

    test "navigates to user management", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      {:ok, users_view, _html} =
        view
        |> element("nav[aria-label='Admin sections'] a", "Users")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users")

      assert has_element?(users_view, "header", "Users")
    end
  end
end
