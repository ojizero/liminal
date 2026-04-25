defmodule LiminalWeb.UserLive.SettingsTest do
  use LiminalWeb.ConnCase

  alias Liminal.Accounts
  import Phoenix.LiveViewTest
  import Liminal.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Save Password"
      assert html =~ "Change Username"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "username" => user.username,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_username_and_password(user.username, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "delete account" do
    test "delete button renders for all users", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert has_element?(view, "#delete-account-btn")
    end

    test "normal user can delete their account", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      view
      |> element("#delete-account-btn")
      |> render_click()

      assert_redirect(view, ~p"/users/log-in")
    end

    test "admin with other admins can delete their account", %{conn: conn} do
      _other_admin = admin_user_fixture(%{username: "other_admin"})
      admin = admin_user_fixture(%{username: "self_del_admin"})

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings")

      view
      |> element("#delete-account-btn")
      |> render_click()

      assert_redirect(view, ~p"/users/log-in")
    end

    test "last admin cannot delete their account", %{conn: conn} do
      admin = admin_user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings")

      view
      |> element("#delete-account-btn")
      |> render_click()

      assert has_element?(view, "#delete-account-btn")
      assert render(view) =~ "You are the last admin"
    end
  end

  describe "become normal user" do
    test "button renders only for admin users", %{conn: conn} do
      admin = admin_user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings")

      assert has_element?(view, "#become-normal-user-btn")
    end

    test "button does NOT render for normal users", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      refute has_element?(view, "#become-normal-user-btn")
    end

    test "admin can become normal user", %{conn: conn} do
      _other_admin = admin_user_fixture(%{username: "stay_admin"})
      admin = admin_user_fixture(%{username: "step_down"})

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings")

      view
      |> element("#become-normal-user-btn")
      |> render_click()

      assert_redirect(view, ~p"/users/settings")

      updated_user = Accounts.get_user!(admin.id)
      assert updated_user.role == "user"
    end

    test "last admin cannot become normal user", %{conn: conn} do
      admin = admin_user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings")

      view
      |> element("#become-normal-user-btn")
      |> render_click()

      assert has_element?(view, "#become-normal-user-btn")
      assert render(view) =~ "You are the last admin"
    end
  end

  describe "update username form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the username", %{conn: conn, user: _user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#username_form", user: %{username: "new_username"})
        |> render_submit()

      assert result =~ "Username updated successfully"
      assert Accounts.get_user_by_username("new_username")
    end

    test "renders errors for invalid username", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#username_form", user: %{username: "bad name!"})
        |> render_submit()

      assert result =~ "only letters, numbers, and underscores allowed"
    end
  end
end
