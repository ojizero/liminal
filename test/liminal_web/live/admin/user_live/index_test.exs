defmodule LiminalWeb.Admin.UserLive.IndexTest do
  use LiminalWeb.ConnCase

  import Phoenix.LiveViewTest
  import Liminal.AccountsFixtures

  describe "unauthenticated" do
    test "redirects from /admin/users to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin/users")
      assert {:redirect, %{to: to}} = redirect
      assert to =~ ~p"/users/register"
    end
  end

  describe "non-admin user" do
    setup :register_and_log_in_user

    test "redirects from /admin/users to home", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin/users")
      assert {:redirect, %{to: to}} = redirect
      assert to == ~p"/"
    end

    test "does NOT see Admin nav link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "a", "Admin")
    end
  end

  describe "admin user - index" do
    setup :register_and_log_in_admin

    test "renders Users header", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")
      assert has_element?(view, "header", "Users")
    end

    test "lists users with role and status badges", %{conn: conn} do
      _regular_user = user_fixture(%{username: "regularjoe"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users", "regularjoe")
      assert has_element?(view, "#users .badge", "user")
      assert has_element?(view, "#users .badge-success", "active")
    end

    test "sees Admin nav link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")
      assert has_element?(view, "a", "Admin")
    end
  end

  describe "admin user - invite user" do
    setup :register_and_log_in_admin

    test "invites a user with valid data and shows invite link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view |> element("a", "Invite User") |> render_click()
      assert has_element?(view, "#admin-invite-user-form")

      view
      |> form("#admin-invite-user-form",
        user: %{
          username: "newuser",
          role: "user"
        }
      )
      |> render_submit()

      assert has_element?(view, "#users", "newuser")
      assert has_element?(view, "input[readonly]")
    end

    test "shows validation errors for invalid input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/new")
      assert has_element?(view, "#admin-invite-user-form")

      view
      |> form("#admin-invite-user-form",
        user: %{
          username: "",
          role: "user"
        }
      )
      |> render_submit()

      assert has_element?(view, "#admin-invite-user-form")
    end
  end

  describe "admin user - make admin" do
    setup :register_and_log_in_admin

    test "makes a regular user an admin", %{conn: conn} do
      _regular_user = user_fixture(%{username: "promoteme"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users", "promoteme")

      view
      |> element("button[phx-click='make_admin']")
      |> render_click()

      assert has_element?(view, "#users .badge-primary", "admin")
    end
  end

  describe "admin user - step down" do
    setup :register_and_log_in_admin

    test "shows step down button for current admin's own row", %{conn: conn, user: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users", admin.username)
      assert has_element?(view, "button[phx-click='step_down']")
    end

    test "does not show any action buttons for other admin rows", %{conn: conn} do
      other_admin = admin_user_fixture(%{username: "otheradmin"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users", "otheradmin")
      refute has_element?(view, "button[phx-click='step_down'][phx-value-id='#{other_admin.id}']")

      refute has_element?(
               view,
               "button[phx-click='make_admin'][phx-value-id='#{other_admin.id}']"
             )

      refute has_element?(view, "button[phx-click='delete'][phx-value-id='#{other_admin.id}']")
    end

    test "stepping down redirects to home with flash", %{conn: conn, user: admin} do
      _other_admin = admin_user_fixture(%{username: "keepadmin"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element("button[phx-click='step_down']")
      |> render_click()

      flash = assert_redirect(view, ~p"/")
      assert flash["info"] == "#{admin.username} is now a normal user."
    end

    test "shows error flash when last admin tries to step down", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element("button[phx-click='step_down']")
      |> render_click()

      assert render(view) =~ "You are the last admin and cannot step down."
    end
  end

  describe "admin user - disable/enable" do
    setup :register_and_log_in_admin

    test "disables a user", %{conn: conn} do
      _regular_user = user_fixture(%{username: "disableme"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users", "disableme")
      assert has_element?(view, "#users .badge-success", "active")

      view
      |> element("button[phx-click='disable']")
      |> render_click()

      assert has_element?(view, "#users .badge-error", "disabled")
    end

    test "enables a disabled user", %{conn: conn} do
      regular_user = user_fixture(%{username: "enableme"})

      Liminal.Repo.update!(
        Ecto.Changeset.change(regular_user, disabled_at: DateTime.utc_now(:second))
      )

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users", "enableme")
      assert has_element?(view, "#users .badge-error", "disabled")

      view
      |> element("button[phx-click='enable']")
      |> render_click()

      assert has_element?(view, "#users .badge-success", "active")
    end
  end

  describe "admin user - delete" do
    setup :register_and_log_in_admin

    test "deletes a user from the stream", %{conn: conn} do
      _regular_user = user_fixture(%{username: "deleteme"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users", "deleteme")

      view
      |> element("button[phx-click='delete']")
      |> render_click()

      refute has_element?(view, "#users", "deleteme")
    end
  end

  describe "admin user - generate reset link" do
    setup :register_and_log_in_admin

    test "displays reset URL inline when clicking Reset Password", %{conn: conn} do
      _regular_user = user_fixture(%{username: "resetme"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users", "resetme")

      view
      |> element("button[phx-click='generate_reset_link']")
      |> render_click()

      assert has_element?(view, "input[readonly]")
    end
  end
end
