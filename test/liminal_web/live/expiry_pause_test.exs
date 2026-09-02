defmodule LiminalWeb.ExpiryPauseTest do
  use LiminalWeb.ConnCase, async: false

  import Liminal.AccountsFixtures
  import Liminal.LinksFixtures
  import Phoenix.LiveViewTest

  alias Liminal.Accounts
  alias Liminal.Accounts.Scope
  alias Liminal.Links

  @day 86_400

  # `time_remaining/1` truncates, so a deadline a whole 20 days out reads as 19.
  @twenty_days_left "19 days"

  setup :ensure_reindex_started!

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user, scope: Scope.for_user(user)}
  end

  describe "settings panel" do
    test "renders the pause controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      assert has_element?(view, "#expiry-pause-settings #expiry-pause-form")

      assert has_element?(
               view,
               "#expiry-pause-form input[type=checkbox][name='expiry_pause[enabled]']"
             )

      assert has_element?(view, "#expiry-pause-form select[name='expiry_pause[days]']")
      refute has_element?(view, "#expiry-pause-status")
      refute has_element?(view, "#expiry-pause-banner")
    end

    test "offers only pause lengths within the cap", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      for {_label, days} <- Links.expiry_pause_duration_options() do
        assert has_element?(view, "#expiry-pause-form select option[value='#{days}']")
      end

      refute has_element?(
               view,
               "#expiry-pause-form select option[value='#{Links.max_expiry_pause_days() + 1}']"
             )
    end

    test "toggling the pause on stores the chosen length", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      html =
        view
        |> form("#expiry-pause-form", expiry_pause: %{enabled: "true", days: "30"})
        |> render_change()

      assert html =~ "Expiries paused until"

      paused = Accounts.get_user!(user.id)
      assert Links.expiry_paused?(paused)
      assert DateTime.diff(paused.expiry_paused_until, paused.expiry_paused_at) == 30 * @day

      assert has_element?(view, "#expiry-pause-status")
      assert has_element?(view, "#settings-resume-expiries")
      assert has_element?(view, "#expiry-pause-banner")
    end

    test "changing the length while paused re-times the window", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> form("#expiry-pause-form", expiry_pause: %{enabled: "true", days: "7"})
      |> render_change()

      view
      |> form("#expiry-pause-form", expiry_pause: %{enabled: "true", days: "60"})
      |> render_change()

      paused = Accounts.get_user!(user.id)
      assert DateTime.diff(paused.expiry_paused_until, paused.expiry_paused_at) == 60 * @day

      settle_pause_broadcast(view)
    end

    test "toggling the pause off resumes expiries", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> form("#expiry-pause-form", expiry_pause: %{enabled: "true", days: "30"})
      |> render_change()

      html =
        view
        |> form("#expiry-pause-form", expiry_pause: %{enabled: "false", days: "30"})
        |> render_change()

      assert html =~ "Expiries resumed."
      refute Links.expiry_paused?(Accounts.get_user!(user.id))
      refute has_element?(view, "#expiry-pause-status")
      refute has_element?(view, "#expiry-pause-banner")
    end

    test "the resume button in the panel ends the pause", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> form("#expiry-pause-form", expiry_pause: %{enabled: "true", days: "30"})
      |> render_change()

      html = view |> element("#settings-resume-expiries") |> render_click()

      assert html =~ "Expiries resumed."
      refute Links.expiry_paused?(Accounts.get_user!(user.id))

      settle_pause_broadcast(view)
    end

    test "a length outside the offered set falls back to the default", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> render_change("pause_expiries", %{
        "expiry_pause" => %{"enabled" => "true", "days" => "9999"}
      })

      paused = Accounts.get_user!(user.id)

      assert DateTime.diff(paused.expiry_paused_until, paused.expiry_paused_at) ==
               Links.default_expiry_pause_days() * @day

      settle_pause_broadcast(view)
    end
  end

  describe "banner" do
    test "shows when expiries are paused and resumes from any page", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      link_fixture(scope)
      {:ok, _paused} = Links.pause_expiries(scope, 30)

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Expiries paused"
      assert has_element?(view, "#expiry-pause-banner")
      assert has_element?(view, "#banner-resume-expiries")

      html = view |> element("#banner-resume-expiries") |> render_click()

      assert html =~ "Expiries resumed."
      refute has_element?(view, "#expiry-pause-banner")
      refute Links.expiry_paused?(Accounts.get_user!(user.id))
    end

    test "stays hidden when expiries are running", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#expiry-pause-banner")
    end

    test "is reachable from the admin area", %{conn: conn} do
      admin = admin_user_fixture()
      {:ok, _paused} = Links.pause_expiries(Scope.for_user(admin), 30)

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

      assert has_element?(view, "#expiry-pause-banner")
      assert view |> element("#banner-resume-expiries") |> render_click() =~ "Expiries resumed."
      refute Links.expiry_paused?(Accounts.get_user!(admin.id))
    end
  end

  describe "link cards" do
    test "report expiry as held rather than counting down", %{conn: conn, scope: scope} do
      tag = tag_fixture(scope, %{expires_in_days: 20})
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      {:ok, paused} = Links.pause_expiries(scope, 30)
      aged = age_expiry_pause(paused, 8 * @day)
      set_link_tag_expiry(link, DateTime.add(aged.expiry_paused_at, 20 * @day, :second))

      {:ok, view, _html} = live(conn, ~p"/")

      expiry = view |> element("#link-expiry-#{link.id}") |> render()

      assert expiry =~ "Paused · #{@twenty_days_left} left"
      assert expiry =~ "#{@twenty_days_left} left when you resume"
      refute expiry =~ "Expires in"
    end

    test "go back to counting down once expiries resume", %{conn: conn, scope: scope} do
      tag = tag_fixture(scope, %{expires_in_days: 20})
      link = link_fixture(scope, %{tag_ids: [tag.id]})
      {:ok, _paused} = Links.pause_expiries(scope, 30)

      {:ok, view, _html} = live(conn, ~p"/")
      assert view |> element("#link-expiry-#{link.id}") |> render() =~ "Paused"

      view |> element("#banner-resume-expiries") |> render_click()

      expiry = view |> element("#link-expiry-#{link.id}") |> render()
      assert expiry =~ "Expires in #{@twenty_days_left}"
      refute expiry =~ "Paused"
    end

    test "pick up a pause started in another session", %{conn: conn, scope: scope} do
      tag = tag_fixture(scope, %{expires_in_days: 20})
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      {:ok, view, _html} = live(conn, ~p"/")
      assert view |> element("#link-expiry-#{link.id}") |> render() =~ "Expires in"

      {:ok, _paused} = Links.pause_expiries(scope, 30)

      assert render(view) =~ "Expiries paused"
      assert view |> element("#link-expiry-#{link.id}") |> render() =~ "Paused"
    end
  end

  # Pause changes broadcast to every session, including the one that made them, so the
  # message is still queued when the triggering event returns. Give the LiveView a
  # round-trip to handle it before the test tears the sandbox down under it.
  defp settle_pause_broadcast(view), do: render(view)
end
