defmodule LiminalWeb.UserLive.ResetPasswordTest do
  use LiminalWeb.ConnCase

  import Phoenix.LiveViewTest
  import Liminal.AccountsFixtures

  alias Liminal.Accounts

  setup do
    admin = admin_user_fixture()
    admin_scope = Accounts.Scope.for_user(admin)
    user = user_fixture()
    token = Accounts.generate_reset_password_token(admin_scope, user)

    %{user: user, token: token, admin_scope: admin_scope}
  end

  describe "valid token" do
    test "renders password reset form", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")
      assert has_element?(view, "#reset-password-form")
    end
  end

  describe "invalid token" do
    test "redirects to login with error flash", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/reset-password/invalidtoken")
      assert {:redirect, %{to: to, flash: flash}} = redirect
      assert to == ~p"/users/log-in"
      assert flash["error"] =~ "invalid or has expired"
    end
  end

  describe "submit valid password" do
    test "resets password and redirects to login", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      view
      |> form("#reset-password-form",
        user: %{
          password: "new_valid_password123",
          password_confirmation: "new_valid_password123"
        }
      )
      |> render_submit()

      flash = assert_redirect(view, ~p"/users/log-in")
      assert flash["info"] =~ "Password reset successfully"
    end
  end

  describe "submit invalid password" do
    test "shows validation error for too short password", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      view
      |> form("#reset-password-form",
        user: %{
          password: "short",
          password_confirmation: "short"
        }
      )
      |> render_submit()

      assert has_element?(view, "#reset-password-form")
    end

    test "shows validation error for confirmation mismatch", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/users/reset-password/#{token}")

      view
      |> form("#reset-password-form",
        user: %{
          password: "new_valid_password123",
          password_confirmation: "different_password123"
        }
      )
      |> render_submit()

      assert has_element?(view, "#reset-password-form")
    end
  end

  describe "disabled user token" do
    test "redirects to login since token query filters disabled users", %{
      conn: conn,
      user: user,
      token: token
    } do
      # Token was generated while user was active (in setup).
      # Now disable the user — the token verification query filters out disabled users.
      Liminal.Repo.update!(Ecto.Changeset.change(user, disabled_at: DateTime.utc_now(:second)))

      assert {:error, redirect} = live(conn, ~p"/users/reset-password/#{token}")
      assert {:redirect, %{to: to, flash: flash}} = redirect
      assert to == ~p"/users/log-in"
      assert flash["error"] =~ "invalid or has expired"
    end
  end
end
