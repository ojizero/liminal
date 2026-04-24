defmodule LiminalWeb.LinkLive.IndexTest do
  use LiminalWeb.ConnCase

  import Phoenix.LiveViewTest
  import Liminal.LinksFixtures

  describe "unauthenticated" do
    test "redirects from /", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/")
      assert {:redirect, %{to: to}} = redirect
      assert to =~ ~p"/users/log-in"
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "renders links page with default categories from registration", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "header", "My Links")
      # Default categories were created at registration time
      categories = Liminal.Links.list_categories(scope)
      assert length(categories) == 3
    end

    test "default filter is Unviewed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      # The Unviewed button should have btn-primary class (active state)
      assert has_element?(view, "button.btn-primary", "Unviewed")
    end

    test "add a link via form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("a", "Add Link") |> render_click()
      assert has_element?(view, "#link-form")

      view
      |> form("#link-form", link: %{url: "https://example.com/test"})
      |> render_submit()

      assert has_element?(view, "#links", "https://example.com/test")
    end

    test "edit a link", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://old.com", title: "Old Title"})
      {:ok, view, _html} = live(conn, ~p"/")
      # Switch to "All" filter to see the link (it's unviewed so should show by default too)

      view |> element("a[href='/links/#{link.id}/edit']") |> render_click()
      assert has_element?(view, "#link-form")

      view
      |> form("#link-form", link: %{title: "New Title"})
      |> render_submit()

      assert has_element?(view, "#links", "New Title")
    end

    test "delete a link", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://delete-me.com", title: "Delete Me"})
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#links", "Delete Me")

      view
      |> element("button[phx-click='delete'][phx-value-id='#{link.id}']")
      |> render_click()

      refute has_element?(view, "#links", "Delete Me")
    end

    test "mark viewed and mark unviewed", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://viewme.com", title: "View Me"})
      {:ok, view, _html} = live(conn, ~p"/")

      # Initially visible in unviewed filter
      assert has_element?(view, "#links", "View Me")

      # Mark as viewed
      view
      |> element("button[phx-click='mark_viewed'][phx-value-id='#{link.id}']")
      |> render_click()

      # Switch to viewed filter to see it
      view |> element("button[phx-click='filter'][phx-value-filter='viewed']") |> render_click()
      assert has_element?(view, "#links", "View Me")

      # Mark unviewed
      view
      |> element("button[phx-click='mark_unviewed'][phx-value-id='#{link.id}']")
      |> render_click()

      # Switch back to unviewed
      view |> element("button[phx-click='filter'][phx-value-filter='unviewed']") |> render_click()
      assert has_element?(view, "#links", "View Me")
    end

    test "tag and untag a link", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://tagme.com", title: "Tag Me"})
      {:ok, view, _html} = live(conn, ~p"/")

      # Default categories created at registration. Get one.
      categories = Liminal.Links.list_categories(scope)
      cat = Enum.find(categories, &(&1.name == "saved for later"))

      # Tag it
      view
      |> element(
        "button[phx-click='tag'][phx-value-link-id='#{link.id}'][phx-value-category-id='#{cat.id}']"
      )
      |> render_click()

      assert has_element?(view, "#links", "saved for later")

      # Untag it
      view
      |> element(
        "button[phx-click='untag'][phx-value-link-id='#{link.id}'][phx-value-category-id='#{cat.id}']"
      )
      |> render_click()

      refute has_element?(view, "#links span", "saved for later")
    end

    test "filter toggles work", %{conn: conn, scope: scope} do
      _link1 = link_fixture(scope, %{url: "https://unviewed.com", title: "Unviewed Link"})
      link2 = link_fixture(scope, %{url: "https://viewed.com", title: "Viewed Link"})
      Liminal.Links.mark_viewed(scope, link2)

      {:ok, view, _html} = live(conn, ~p"/")

      # Default: unviewed only
      assert has_element?(view, "#links", "Unviewed Link")
      refute has_element?(view, "#links", "Viewed Link")

      # All filter
      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()
      assert has_element?(view, "#links", "Unviewed Link")
      assert has_element?(view, "#links", "Viewed Link")

      # Viewed filter
      view |> element("button[phx-click='filter'][phx-value-filter='viewed']") |> render_click()
      refute has_element?(view, "#links", "Unviewed Link")
      assert has_element?(view, "#links", "Viewed Link")
    end
  end
end
