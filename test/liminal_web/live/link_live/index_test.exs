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

    test "add a link via form with category selection", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")

      categories = Liminal.Links.list_categories(scope)
      cat = hd(categories)

      view |> element("a", "Add Link") |> render_click()
      assert has_element?(view, "#link-form")

      # Select a category
      view
      |> element("input[type='checkbox'][phx-value-id='#{cat.id}']")
      |> render_click()

      view
      |> form("#link-form", link: %{url: "https://example.com/test"})
      |> render_submit()

      assert has_element?(view, "#links", "https://example.com/test")
    end

    test "add a link without selecting categories shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("a", "Add Link") |> render_click()
      assert has_element?(view, "#link-form")

      view
      |> form("#link-form", link: %{url: "https://example.com/no-cats"})
      |> render_submit()

      # Should show an error flash
      assert render(view) =~ "Select at least one category"
    end

    test "category checkboxes shown on new link form", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/links/new")

      categories = Liminal.Links.list_categories(scope)

      for cat <- categories do
        assert has_element?(view, "input[type='checkbox'][phx-value-id='#{cat.id}']")
      end
    end

    test "edit a link", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://old.com", title: "Old Title"})
      {:ok, view, _html} = live(conn, ~p"/")

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

    test "tag and untag a link (with remaining categories)", %{conn: conn, scope: scope} do
      # Create link with a category so it has at least one
      categories = Liminal.Links.list_categories(scope)
      cat1 = Enum.at(categories, 0)
      cat2 = Enum.at(categories, 1)

      link =
        link_fixture(scope, %{url: "https://tagme.com", title: "Tag Me", category_ids: [cat1.id]})

      {:ok, view, _html} = live(conn, ~p"/")

      # Tag with second category
      view
      |> element(
        "button[phx-click='tag'][phx-value-link-id='#{link.id}'][phx-value-category-id='#{cat2.id}']"
      )
      |> render_click()

      assert has_element?(view, "#links", cat2.name)

      # Untag second category (link still has cat1)
      view
      |> element(
        "button[phx-click='untag'][phx-value-link-id='#{link.id}'][phx-value-category-id='#{cat2.id}']"
      )
      |> render_click()

      refute has_element?(view, "#links span", cat2.name)
      # Link should still exist
      assert has_element?(view, "#links", "Tag Me")
    end

    test "untag last category deletes the link", %{conn: conn, scope: scope} do
      category = category_fixture(scope)

      link =
        link_fixture(scope, %{
          url: "https://last-cat.com",
          title: "Last Cat",
          category_ids: [category.id]
        })

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#links", "Last Cat")

      # Untag the only category
      view
      |> element(
        "button[phx-click='untag'][phx-value-link-id='#{link.id}'][phx-value-category-id='#{category.id}']"
      )
      |> render_click()

      # Link should be removed from the page
      refute has_element?(view, "#links", "Last Cat")
      assert render(view) =~ "Last category removed"
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
