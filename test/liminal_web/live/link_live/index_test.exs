defmodule LiminalWeb.LinkLive.IndexTest do
  use LiminalWeb.ConnCase

  import Phoenix.LiveViewTest
  import Liminal.LinksFixtures

  describe "unauthenticated" do
    test "redirects from /", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/")
      assert {:redirect, %{to: to}} = redirect
      assert to =~ ~p"/users/register"
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "renders links page with default tags from registration", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "header", "My Links")
      # Default tags were created at registration time
      tags = Liminal.Links.list_tags(scope)
      assert length(tags) == 3
    end

    test "default filter is Unviewed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      # The Unviewed button should have btn-primary class (active state)
      assert has_element?(view, "button.btn-primary", "Unviewed")
    end

    test "add a link via form with tag selection", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")

      tags = Liminal.Links.list_tags(scope)
      tag = hd(tags)

      view |> element("a", "Add Link") |> render_click()
      assert has_element?(view, "#link-form")

      # Select a tag
      view
      |> element("input[type='checkbox'][phx-value-id='#{tag.id}']")
      |> render_click()

      view
      |> form("#link-form", link: %{url: "https://example.com/test"})
      |> render_submit()

      assert has_element?(view, "#links", "https://example.com/test")
    end

    test "add a link without selecting tags shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("a", "Add Link") |> render_click()
      assert has_element?(view, "#link-form")

      view
      |> form("#link-form", link: %{url: "https://example.com/no-tags"})
      |> render_submit()

      # Should show an error flash
      assert render(view) =~ "Select at least one tag"
    end

    test "tag checkboxes shown on new link form", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/links/new")

      tags = Liminal.Links.list_tags(scope)

      for tag <- tags do
        assert has_element?(view, "input[type='checkbox'][phx-value-id='#{tag.id}']")
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

    test "tag and untag a link (with remaining tags)", %{conn: conn, scope: scope} do
      # Create link with a tag so it has at least one
      tags = Liminal.Links.list_tags(scope)
      tag1 = Enum.at(tags, 0)
      tag2 = Enum.at(tags, 1)

      link =
        link_fixture(scope, %{url: "https://tagme.com", title: "Tag Me", tag_ids: [tag1.id]})

      {:ok, view, _html} = live(conn, ~p"/")

      # Tag with second tag
      view
      |> element(
        "button[phx-click='tag'][phx-value-link-id='#{link.id}'][phx-value-tag-id='#{tag2.id}']"
      )
      |> render_click()

      assert has_element?(view, "#links", tag2.name)

      # Untag second tag (link still has tag1)
      view
      |> element(
        "button[phx-click='untag'][phx-value-link-id='#{link.id}'][phx-value-tag-id='#{tag2.id}']"
      )
      |> render_click()

      refute has_element?(view, "#links span", tag2.name)
      # Link should still exist
      assert has_element?(view, "#links", "Tag Me")
    end

    test "untag last tag deletes the link", %{conn: conn, scope: scope} do
      tag = tag_fixture(scope)

      link =
        link_fixture(scope, %{
          url: "https://last-tag.com",
          title: "Last Tag",
          tag_ids: [tag.id]
        })

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#links", "Last Tag")

      # Untag the only tag
      view
      |> element(
        "button[phx-click='untag'][phx-value-link-id='#{link.id}'][phx-value-tag-id='#{tag.id}']"
      )
      |> render_click()

      # Link should be removed from the page
      refute has_element?(view, "#links", "Last Tag")
      assert render(view) =~ "Last tag removed"
    end

    test "link deleted via PubSub is removed from the stream", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://cross-session.com", title: "Cross Session"})
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#links", "Cross Session")

      # Simulate deletion from another session/janitor
      Phoenix.PubSub.broadcast(
        Liminal.PubSub,
        "user_links:#{scope.user.id}",
        {:link_deleted, link.id}
      )

      render(view)
      refute has_element?(view, "#links", "Cross Session")
    end

    test "link_created broadcast adds link to stream", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")
      tag = tag_fixture(scope)

      link =
        link_fixture(scope, %{
          url: "https://broadcast-create.com",
          title: "Broadcast Create",
          tag_ids: [tag.id]
        })

      refetched = Liminal.Links.get_link!(scope, link.id)

      Phoenix.PubSub.broadcast(
        Liminal.PubSub,
        "user_links:#{scope.user.id}",
        {:link_created, refetched}
      )

      render(view)
      assert has_element?(view, "#links", "Broadcast Create")
    end

    test "link_updated broadcast updates link in stream", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://update-me.com", title: "Update Me"})
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#links", "Update Me")

      updated_link = %{Liminal.Links.get_link!(scope, link.id) | title: "Updated Title"}

      Phoenix.PubSub.broadcast(
        Liminal.PubSub,
        "user_links:#{scope.user.id}",
        {:link_updated, updated_link}
      )

      render(view)
      assert has_element?(view, "#links", "Updated Title")
    end

    test "link_updated broadcast removes link from unviewed filter when viewed", %{
      conn: conn,
      scope: scope
    } do
      link =
        link_fixture(scope, %{url: "https://viewed-broadcast.com", title: "Will Be Viewed"})

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#links", "Will Be Viewed")

      # Simulate receiving a broadcast where the link is now viewed
      viewed_link = %{
        Liminal.Links.get_link!(scope, link.id)
        | viewed_at: DateTime.utc_now(:second)
      }

      Phoenix.PubSub.broadcast(
        Liminal.PubSub,
        "user_links:#{scope.user.id}",
        {:link_updated, viewed_link}
      )

      render(view)
      refute has_element?(view, "#links", "Will Be Viewed")
    end

    test "link_created broadcast does NOT add to viewed filter", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to viewed filter
      view
      |> element("button[phx-click='filter'][phx-value-filter='viewed']")
      |> render_click()

      tag = tag_fixture(scope)

      link =
        link_fixture(scope, %{
          url: "https://new-unviewed.com",
          title: "New Unviewed",
          tag_ids: [tag.id]
        })

      refetched = Liminal.Links.get_link!(scope, link.id)

      Phoenix.PubSub.broadcast(
        Liminal.PubSub,
        "user_links:#{scope.user.id}",
        {:link_created, refetched}
      )

      render(view)
      refute has_element?(view, "#links", "New Unviewed")
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
