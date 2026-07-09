defmodule LiminalWeb.UserLive.SettingsTest do
  use LiminalWeb.ConnCase, async: false

  alias Liminal.Accounts
  import Phoenix.LiveViewTest
  import Liminal.AccountsFixtures

  setup :ensure_reindex_started!

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert has_element?(view, "#settings-page")
      assert has_element?(view, "#account-security")
      assert has_element?(view, "#username-settings #username_form")
      assert has_element?(view, "#password-settings #password_form")
      assert has_element?(view, "#preferences-settings #settings_form")
      assert has_element?(view, "#user-menu a[aria-current='page']", "Settings")
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/register"
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

  describe "reindex links" do
    setup %{conn: conn} do
      user = user_fixture()
      scope = Liminal.Accounts.Scope.for_user(user)
      %{conn: log_in_user(conn, user), user: user, scope: scope}
    end

    test "renders reindex controls on settings page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      assert has_element?(view, "#user-reindex")
      assert has_element?(view, "#user-reindex-failed-btn")
      assert has_element?(view, "#user-reindex-all-btn")
    end

    test "starts a user-scoped failed reindex job", %{conn: conn, scope: scope} do
      import Ecto.Query

      tag = Liminal.LinksFixtures.tag_fixture(scope)

      {:ok, link1} =
        Liminal.Links.create_link(scope, %{url: "https://user-fail-one.example.com"}, [tag.id])

      {:ok, link2} =
        Liminal.Links.create_link(scope, %{url: "https://user-fail-two.example.com"}, [tag.id])

      now = DateTime.utc_now(:second)

      for link <- [link1, link2] do
        Liminal.Repo.update_all(
          from(l in Liminal.Links.Link, where: l.id == ^link.id),
          set: [index_attempt_count: 1, index_last_attempted_at: now]
        )
      end

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view |> element("#user-reindex-failed-btn") |> render_click()

      assert has_element?(view, "#user-reindex-status", "Running")
      assert has_element?(view, "#user-reindex-failed-btn[disabled]")
      assert has_element?(view, "#user-reindex-all-btn[disabled]")
    end

    test "user can cancel their own reindex job", %{conn: conn, scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)

      {:ok, _} =
        Liminal.Links.create_link(scope, %{url: "https://user-cancel.example.com"}, [tag.id])

      {:ok, _} =
        Liminal.Links.create_link(scope, %{url: "https://user-cancel-2.example.com"}, [tag.id])

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view |> element("#user-reindex-all-btn") |> render_click()
      assert has_element?(view, "#user-reindex-status", "Running")

      view |> element("#user-reindex-cancel-btn") |> render_click()
      refute has_element?(view, "#user-reindex-status", "Running")
    end
  end

  describe "preferences form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders the auto-mark-viewed toggle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      assert has_element?(view, "#settings_form")

      assert has_element?(
               view,
               "#settings_form input[type=checkbox][name='user[auto_mark_viewed_on_open]']"
             )
    end

    test "toggling the preference persists it", %{conn: conn, user: user} do
      refute user.auto_mark_viewed_on_open

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      result =
        view
        |> form("#settings_form", user: %{auto_mark_viewed_on_open: "true"})
        |> render_change()

      assert result =~ "Preferences updated."
      assert Accounts.get_user!(user.id).auto_mark_viewed_on_open == true

      view
      |> form("#settings_form", user: %{auto_mark_viewed_on_open: "false"})
      |> render_change()

      assert Accounts.get_user!(user.id).auto_mark_viewed_on_open == false
    end

    test "renders default tag preference controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      assert has_element?(
               view,
               "#settings_form input[type=checkbox][name='user[default_tags_enabled]']"
             )

      refute render(view) =~ "Default tag"
    end

    test "enabling default tags requires selecting a tag", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> element("#settings_form")
      |> render_change(%{"user" => %{"default_tags_enabled" => "true"}})

      refute Accounts.get_user!(user.id).default_tags_enabled
    end

    test "enabling default tags persists the chosen tag", %{conn: conn, user: user} do
      scope = Liminal.Accounts.Scope.for_user(user)
      [tag | _] = Liminal.Links.list_tags(scope)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> element("#settings_form")
      |> render_change(%{"user" => %{"default_tags_enabled" => "true"}})

      view
      |> element("#settings_form")
      |> render_change(%{
        "user" => %{"default_tags_enabled" => "true", "default_tag_id" => to_string(tag.id)}
      })

      updated = Accounts.get_user!(user.id)
      assert updated.default_tags_enabled
      assert updated.default_tag_id == tag.id
    end

    test "disabling default tags clears the stored tag", %{conn: conn, user: user} do
      scope = Liminal.Accounts.Scope.for_user(user)
      [tag | _] = Liminal.Links.list_tags(scope)

      {:ok, _} =
        Accounts.update_user_settings(user, %{
          default_tags_enabled: true,
          default_tag_id: tag.id
        })

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> form("#settings_form", user: %{default_tags_enabled: "false"})
      |> render_change()

      updated = Accounts.get_user!(user.id)
      refute updated.default_tags_enabled
      assert is_nil(updated.default_tag_id)
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
