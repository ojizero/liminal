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

      assert has_element?(view, "#link-form")

      # Select a tag
      view
      |> element("button[phx-click='toggle_tag'][phx-value-id='#{tag.id}']")
      |> render_click()

      view
      |> form("#link-form", link: %{url: "https://example.com/test"})
      |> render_submit()

      assert has_element?(view, "#links", "https://example.com/test")
    end

    test "add a link with an optional note", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")

      tag = hd(Liminal.Links.list_tags(scope))

      view
      |> element("button[phx-click='toggle_tag'][phx-value-id='#{tag.id}']")
      |> render_click()

      view
      |> form("#link-form",
        link: %{url: "https://example.com/with-note", note: "Remember why I saved this"}
      )
      |> render_submit()

      assert has_element?(view, "#links", "Remember why I saved this")

      saved = Liminal.Links.find_link_by_url(scope, "https://example.com/with-note")
      assert saved.note == "Remember why I saved this"
    end

    test "duplicate URL shows confirmation modal", %{conn: conn, scope: scope} do
      tag = tag_fixture(scope)
      existing = link_fixture(scope, %{url: "https://example.org", tag_ids: [tag.id]})

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-click='toggle_tag'][phx-value-id='#{tag.id}']")
      |> render_click()

      view
      |> form("#link-form", link: %{url: "https://example.org"})
      |> render_submit()

      assert has_element?(view, "#duplicate-link-modal")
      assert render(view) =~ "Link already exists"

      links =
        Liminal.Links.list_links(scope, filter: :all)
        |> Enum.filter(&(&1.url == "https://example.org"))

      assert length(links) == 1
      assert hd(links).id == existing.id
    end

    test "confirming duplicate merge updates tags on existing link", %{conn: conn, scope: scope} do
      foo = tag_fixture(scope, %{name: "foo"})
      bar = tag_fixture(scope, %{name: "bar"})
      baz = tag_fixture(scope, %{name: "baz"})

      existing =
        link_fixture(scope, %{
          url: "https://example.org",
          tag_ids: [foo.id, bar.id]
        })

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-click='toggle_tag'][phx-value-id='#{foo.id}']")
      |> render_click()

      view
      |> element("button[phx-click='toggle_tag'][phx-value-id='#{baz.id}']")
      |> render_click()

      view
      |> form("#link-form", link: %{url: "https://example.org"})
      |> render_submit()

      assert has_element?(view, "#duplicate-link-modal")

      view
      |> element("button[phx-click='confirm_duplicate_merge']")
      |> render_click()

      refetched = Liminal.Links.get_link!(scope, existing.id)
      tag_names = Enum.map(refetched.link_tags, & &1.tag.name) |> Enum.sort()
      assert tag_names == ["bar", "baz", "foo"]
      assert render(view) =~ "Link updated"
    end

    test "discarding duplicate leaves existing link unchanged", %{conn: conn, scope: scope} do
      tag = tag_fixture(scope)
      existing = link_fixture(scope, %{url: "https://example.org", tag_ids: [tag.id]})

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-click='toggle_tag'][phx-value-id='#{tag.id}']")
      |> render_click()

      view
      |> form("#link-form", link: %{url: "https://example.org"})
      |> render_submit()

      assert has_element?(view, "#duplicate-link-modal")

      view
      |> element("button[phx-click='discard_duplicate']")
      |> render_click()

      refute has_element?(view, "#duplicate-link-modal")

      refetched = Liminal.Links.get_link!(scope, existing.id)
      assert length(refetched.link_tags) == 1
    end

    test "add a link without selecting tags shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#link-form")

      view
      |> form("#link-form", link: %{url: "https://example.com/no-tags"})
      |> render_submit()

      # Should show an error flash
      assert render(view) =~ "Select at least one tag"
    end

    test "tag pills shown on new link form", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")

      tags = Liminal.Links.list_tags(scope)

      for tag <- tags do
        assert has_element?(view, "button[phx-click='toggle_tag'][phx-value-id='#{tag.id}']")
      end
    end

    test "renders platform-specific keyboard shortcut hints for link form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#link-url-paste-shortcut")
      refute has_element?(view, "#link-url-focus-shortcut")

      view
      |> element("#link-shortcuts")
      |> render_hook("set_shortcut_platform", %{
        "platform" => "mac",
        "show_paste_shortcut_hint" => true
      })

      assert has_element?(view, "#link-url-paste-shortcut kbd", "⌘")
      assert has_element?(view, "#link-url-paste-shortcut kbd", "V")
      assert has_element?(view, "#link-url-focus-shortcut kbd", "⌘")
      assert has_element?(view, "#link-url-focus-shortcut kbd", "K")
      refute render(view) =~ "Super"
      refute render(view) =~ "Ctrl"
      refute render(view) =~ "Mod"

      view
      |> element("#link-shortcuts")
      |> render_hook("set_shortcut_platform", %{
        "platform" => "linux",
        "show_paste_shortcut_hint" => true
      })

      html = render(view)
      assert html =~ "Super"
      assert html =~ "Shift"
      assert has_element?(view, "#link-url-focus-shortcut kbd", "K")
      refute html =~ "⌘"

      view
      |> element("#link-shortcuts")
      |> render_hook("set_shortcut_platform", %{
        "platform" => "windows",
        "show_paste_shortcut_hint" => true
      })

      html = render(view)
      assert html =~ "Ctrl"
      assert html =~ "Shift"
      assert has_element?(view, "#link-url-focus-shortcut kbd", "K")
      assert has_element?(view, "#link-url-paste-shortcut kbd", "V")
      refute html =~ "Super"
    end

    test "hides paste shortcut hint on touch-first devices without a hardware keyboard", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#link-shortcuts")
      |> render_hook("set_shortcut_platform", %{
        "platform" => "mac",
        "show_paste_shortcut_hint" => false
      })

      refute has_element?(view, "#link-url-paste-shortcut")
      assert has_element?(view, "#link-url-focus-shortcut kbd", "⌘")
      assert has_element?(view, "#link-url-focus-shortcut kbd", "K")
    end

    test "shortcut focus event pushes client focus event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#link-shortcuts")
      |> render_hook("shortcut_focus_new_link", %{})

      assert_push_event(view, "focus-new-link-url", %{scroll: true})
    end

    test "paste shortcut fills new link form and focuses it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#link-shortcuts")
      |> render_hook("shortcut_paste_link", %{"url" => "https://example.com/pasted"})

      assert has_element?(view, "#link_url[value='https://example.com/pasted']")
      assert_push_event(view, "focus-new-link-url", %{scroll: true})
    end

    test "paste shortcut normalizes urls without a scheme", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#link-shortcuts")
      |> render_hook("shortcut_paste_link", %{"url" => "example.com/no-scheme"})

      assert has_element?(view, "#link_url[value='https://example.com/no-scheme']")
    end

    test "paste shortcut without a link shows an error flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#link-shortcuts")
      |> render_hook("shortcut_paste_no_link", %{})

      assert render(view) =~ "Clipboard does not contain a link"
    end

    test "mod+shift+digit shortcut toggles new-link tag selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#masonry")
      |> render_hook("handle_shortcut_keydown", %{
        "key" => "1",
        "code" => "Digit1",
        "metaKey" => true,
        "ctrlKey" => false,
        "shiftKey" => true,
        "altKey" => false,
        "repeat" => false,
        "platform" => "MacIntel",
        "targetTagName" => "BODY",
        "targetType" => nil,
        "targetIsContentEditable" => false
      })

      view
      |> form("#link-form", link: %{url: "https://example.com/shortcut-tag"})
      |> render_submit()

      assert has_element?(view, "#links", "https://example.com/shortcut-tag")
    end

    test "shortcut parsing supports numpad digits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#masonry")
      |> render_hook("handle_shortcut_keydown", %{
        "key" => "1",
        "code" => "Numpad1",
        "metaKey" => true,
        "ctrlKey" => false,
        "shiftKey" => true,
        "altKey" => false,
        "repeat" => false,
        "platform" => "MacIntel",
        "targetTagName" => "BODY",
        "targetType" => nil,
        "targetIsContentEditable" => false
      })

      view
      |> form("#link-form", link: %{url: "https://example.com/shortcut-numpad"})
      |> render_submit()

      assert has_element?(view, "#links", "https://example.com/shortcut-numpad")
    end

    test "shortcut parsing supports shifted symbol digits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#masonry")
      |> render_hook("handle_shortcut_keydown", %{
        "key" => "!",
        "code" => "Digit1",
        "metaKey" => true,
        "ctrlKey" => false,
        "shiftKey" => true,
        "altKey" => false,
        "repeat" => false,
        "platform" => "MacIntel",
        "targetTagName" => "INPUT",
        "targetType" => "url",
        "targetIsContentEditable" => false
      })

      view
      |> form("#link-form", link: %{url: "https://example.com/shortcut-shift-symbol"})
      |> render_submit()

      assert has_element?(view, "#links", "https://example.com/shortcut-shift-symbol")
    end

    test "hook event toggles tag by index for focused input scenario", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("#link-shortcuts")
      |> render_hook("shortcut_toggle_tag_by_index", %{"index" => 1})

      view
      |> form("#link-form", link: %{url: "https://example.com/shortcut-hook"})
      |> render_submit()

      assert has_element?(view, "#links", "https://example.com/shortcut-hook")
    end

    test "edit a link", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://old.com", title: "Old Title"})
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("a[href='/links/#{link.id}/edit']") |> render_click()
      assert has_element?(view, "#edit-link-form")

      view
      |> form("#edit-link-form", edit_link: %{title: "New Title"})
      |> render_submit()

      assert has_element?(view, "#links", "New Title")
    end

    test "edit a link to add a note", %{conn: conn, scope: scope} do
      link = link_fixture(scope, %{url: "https://note-edit.com", title: "Note Edit"})
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("a[href='/links/#{link.id}/edit']") |> render_click()
      assert has_element?(view, "#edit-link-form")

      view
      |> form("#edit-link-form", edit_link: %{note: "Added on edit"})
      |> render_submit()

      assert has_element?(view, "#links", "Added on edit")
      assert Liminal.Links.get_link!(scope, link.id).note == "Added on edit"
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

      refute has_element?(view, "#links .badge", tag2.name)
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

    # ------------------------------------------------------------------
    # Tag filter tests
    # ------------------------------------------------------------------

    test "tag filter chips appear for user's tags", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")

      tags = Liminal.Links.list_tags(scope)

      for tag <- tags do
        assert has_element?(
                 view,
                 "button[phx-click='toggle_filter_tag'][phx-value-id='#{tag.id}']",
                 tag.name
               )
      end
    end

    test "clicking a tag chip filters links to that tag", %{conn: conn, scope: scope} do
      tag1 = tag_fixture(scope, %{name: "filter-alpha"})
      tag2 = tag_fixture(scope, %{name: "filter-beta"})

      _link1 = link_fixture(scope, %{title: "Link One", tag_ids: [tag1.id]})
      _link2 = link_fixture(scope, %{title: "Link Two", tag_ids: [tag2.id]})

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to "All" so both links are visible regardless of viewed state
      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()
      assert has_element?(view, "#links", "Link One")
      assert has_element?(view, "#links", "Link Two")

      # Click tag1 chip
      view
      |> element("button[phx-click='toggle_filter_tag'][phx-value-id='#{tag1.id}']")
      |> render_click()

      assert has_element?(view, "#links", "Link One")
      refute has_element?(view, "#links", "Link Two")
    end

    test "toggling tag chip off shows all links again", %{conn: conn, scope: scope} do
      tag1 = tag_fixture(scope, %{name: "toggle-alpha"})
      tag2 = tag_fixture(scope, %{name: "toggle-beta"})

      _link1 = link_fixture(scope, %{title: "Toggle One", tag_ids: [tag1.id]})
      _link2 = link_fixture(scope, %{title: "Toggle Two", tag_ids: [tag2.id]})

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to "All" filter
      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      # Toggle tag1 on
      view
      |> element("button[phx-click='toggle_filter_tag'][phx-value-id='#{tag1.id}']")
      |> render_click()

      assert has_element?(view, "#links", "Toggle One")
      refute has_element?(view, "#links", "Toggle Two")

      # Toggle tag1 off again
      view
      |> element("button[phx-click='toggle_filter_tag'][phx-value-id='#{tag1.id}']")
      |> render_click()

      assert has_element?(view, "#links", "Toggle One")
      assert has_element?(view, "#links", "Toggle Two")
    end

    test "multiple tag chips filter with union (any match)", %{conn: conn, scope: scope} do
      tag1 = tag_fixture(scope, %{name: "union-alpha"})
      tag2 = tag_fixture(scope, %{name: "union-beta"})
      tag3 = tag_fixture(scope, %{name: "union-gamma"})

      _link1 = link_fixture(scope, %{title: "Union One", tag_ids: [tag1.id]})
      _link2 = link_fixture(scope, %{title: "Union Two", tag_ids: [tag2.id]})
      _link3 = link_fixture(scope, %{title: "Union Three", tag_ids: [tag3.id]})

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to "All" filter
      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      # Toggle tag1 and tag2
      view
      |> element("button[phx-click='toggle_filter_tag'][phx-value-id='#{tag1.id}']")
      |> render_click()

      view
      |> element("button[phx-click='toggle_filter_tag'][phx-value-id='#{tag2.id}']")
      |> render_click()

      assert has_element?(view, "#links", "Union One")
      assert has_element?(view, "#links", "Union Two")
      refute has_element?(view, "#links", "Union Three")
    end

    # ------------------------------------------------------------------
    # Sort tests
    # ------------------------------------------------------------------

    test "sort form wraps the select with phx-change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "form#sort-form[phx-change='sort']")
      assert has_element?(view, "form#sort-form select[name='sort']")
    end

    test "default sort is newest first", %{conn: conn, scope: scope} do
      older_link = link_fixture(scope, %{title: "Older Default"})
      _newer_link = link_fixture(scope, %{title: "Newer Default"})

      past = DateTime.utc_now(:second) |> DateTime.add(-1, :hour)

      import Ecto.Query

      Liminal.Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^older_link.id),
        set: [inserted_at: past]
      )

      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      html = render(view)
      newer_pos = :binary.match(html, "Newer Default") |> elem(0)
      older_pos = :binary.match(html, "Older Default") |> elem(0)

      assert newer_pos < older_pos,
             "Expected 'Newer Default' before 'Older Default' in default newest-first sort"
    end

    test "sort dropdown changes link ordering", %{conn: conn, scope: scope} do
      older_link = link_fixture(scope, %{title: "Older Link"})
      _newer_link = link_fixture(scope, %{title: "Newer Link"})

      # Backdate older_link's inserted_at
      past = DateTime.utc_now(:second) |> DateTime.add(-1, :hour)

      import Ecto.Query

      Liminal.Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^older_link.id),
        set: [inserted_at: past]
      )

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to "All" filter
      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      # Sort oldest first
      view
      |> element("#sort-form")
      |> render_change(%{"sort" => "time_added_asc"})

      html = render(view)
      older_pos = :binary.match(html, "Older Link") |> elem(0)
      newer_pos = :binary.match(html, "Newer Link") |> elem(0)

      assert older_pos < newer_pos,
             "Expected 'Older Link' to appear before 'Newer Link' when sorted oldest first"
    end

    test "sort by expiring soon orders by link expiry", %{conn: conn, scope: scope} do
      tag_soon = tag_fixture(scope, %{name: "expiring-soon-tag", expires_in_days: 3})
      tag_later = tag_fixture(scope, %{name: "expiring-later-tag", expires_in_days: 30})

      _link_soon =
        link_fixture(scope, %{title: "Expiring Soon Link", tag_ids: [tag_soon.id]})

      _link_later =
        link_fixture(scope, %{title: "Expiring Later Link", tag_ids: [tag_later.id]})

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to "All" filter
      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      # Sort by expiring soon
      view
      |> element("#sort-form")
      |> render_change(%{"sort" => "expiring_soon"})

      html = render(view)
      soon_pos = :binary.match(html, "Expiring Soon Link") |> elem(0)
      later_pos = :binary.match(html, "Expiring Later Link") |> elem(0)

      assert soon_pos < later_pos,
             "Expected 'Expiring Soon Link' to appear before 'Expiring Later Link'"
    end

    test "sort newest first reverses oldest first ordering", %{conn: conn, scope: scope} do
      older_link = link_fixture(scope, %{title: "Reverse Older"})
      _newer_link = link_fixture(scope, %{title: "Reverse Newer"})

      past = DateTime.utc_now(:second) |> DateTime.add(-1, :hour)

      import Ecto.Query

      Liminal.Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^older_link.id),
        set: [inserted_at: past]
      )

      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      # Sort oldest first
      view |> element("#sort-form") |> render_change(%{"sort" => "time_added_asc"})

      html = render(view)

      assert :binary.match(html, "Reverse Older") |> elem(0) <
               :binary.match(html, "Reverse Newer") |> elem(0)

      # Sort newest first again
      view |> element("#sort-form") |> render_change(%{"sort" => "time_added_desc"})

      html = render(view)

      assert :binary.match(html, "Reverse Newer") |> elem(0) <
               :binary.match(html, "Reverse Older") |> elem(0)
    end

    test "sort persists across filter changes", %{conn: conn, scope: scope} do
      older_link = link_fixture(scope, %{title: "Persist Older"})
      _newer_link = link_fixture(scope, %{title: "Persist Newer"})

      past = DateTime.utc_now(:second) |> DateTime.add(-1, :hour)

      import Ecto.Query

      Liminal.Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^older_link.id),
        set: [inserted_at: past]
      )

      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      # Sort oldest first
      view |> element("#sort-form") |> render_change(%{"sort" => "time_added_asc"})

      # Switch filter to unviewed — sort should be preserved
      view
      |> element("button[phx-click='filter'][phx-value-filter='unviewed']")
      |> render_click()

      html = render(view)

      assert :binary.match(html, "Persist Older") |> elem(0) <
               :binary.match(html, "Persist Newer") |> elem(0)
    end

    test "all sort options preserve all links (no items lost)", %{conn: conn, scope: scope} do
      _link1 = link_fixture(scope, %{title: "Preserve Alpha"})
      _link2 = link_fixture(scope, %{title: "Preserve Beta"})

      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      for sort <- ["time_added_desc", "time_added_asc", "expiring_soon"] do
        view |> element("#sort-form") |> render_change(%{"sort" => sort})

        assert has_element?(view, "#links", "Preserve Alpha"),
               "Lost 'Preserve Alpha' after sorting by #{sort}"

        assert has_element?(view, "#links", "Preserve Beta"),
               "Lost 'Preserve Beta' after sorting by #{sort}"
      end
    end

    # ------------------------------------------------------------------
    # Combined filter + sort tests
    # ------------------------------------------------------------------

    test "tag filter and sort work together", %{conn: conn, scope: scope} do
      tag1 = tag_fixture(scope, %{name: "combo-alpha"})
      tag2 = tag_fixture(scope, %{name: "combo-beta"})

      link_a = link_fixture(scope, %{title: "Combo A", tag_ids: [tag1.id]})
      _link_b = link_fixture(scope, %{title: "Combo B", tag_ids: [tag1.id]})
      _link_c = link_fixture(scope, %{title: "Combo C", tag_ids: [tag2.id]})

      # Backdate link_a so it's the oldest
      past = DateTime.utc_now(:second) |> DateTime.add(-1, :hour)

      import Ecto.Query

      Liminal.Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^link_a.id),
        set: [inserted_at: past]
      )

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to "All" filter
      view |> element("button[phx-click='filter'][phx-value-filter='all']") |> render_click()

      # Filter by tag1
      view
      |> element("button[phx-click='toggle_filter_tag'][phx-value-id='#{tag1.id}']")
      |> render_click()

      # Sort oldest first
      view
      |> element("#sort-form")
      |> render_change(%{"sort" => "time_added_asc"})

      html = render(view)

      # Combo C should not be visible (wrong tag)
      refute html =~ "Combo C"

      # Combo A should appear before Combo B (oldest first)
      a_pos = :binary.match(html, "Combo A") |> elem(0)
      b_pos = :binary.match(html, "Combo B") |> elem(0)

      assert a_pos < b_pos,
             "Expected 'Combo A' to appear before 'Combo B' when sorted oldest first"
    end

    # ------------------------------------------------------------------
    # PubSub + tag filter tests
    # ------------------------------------------------------------------

    test "link_created broadcast respects tag filter", %{conn: conn, scope: scope} do
      tag1 = tag_fixture(scope, %{name: "pubsub-alpha"})
      tag2 = tag_fixture(scope, %{name: "pubsub-beta"})

      {:ok, view, _html} = live(conn, ~p"/")

      # Toggle tag1 filter — only links with tag1 should appear
      view
      |> element("button[phx-click='toggle_filter_tag'][phx-value-id='#{tag1.id}']")
      |> render_click()

      # Create a link with tag2 (does NOT match the active filter)
      link =
        link_fixture(scope, %{
          title: "Broadcast No Match",
          tag_ids: [tag2.id]
        })

      refetched = Liminal.Links.get_link!(scope, link.id)

      Phoenix.PubSub.broadcast(
        Liminal.PubSub,
        "user_links:#{scope.user.id}",
        {:link_created, refetched}
      )

      render(view)
      refute has_element?(view, "#links", "Broadcast No Match")
    end

    test "shows indexing failed badge and retry button for gave-up links", %{
      conn: conn,
      scope: scope
    } do
      link = link_fixture(scope, %{url: "https://blocked.example.com", title: "Blocked"})
      now = DateTime.utc_now(:second)

      import Ecto.Query

      Liminal.Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [
          index_attempt_count: 10,
          index_gave_up_at: now,
          index_last_attempted_at: now
        ]
      )

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#links", "Indexing failed")
      assert has_element?(view, "button[phx-click='retry_indexing'][phx-value-id='#{link.id}']")
    end
  end

  describe "auto mark viewed on open" do
    test "anchors do NOT carry open_link when preference disabled", %{conn: conn} do
      user = Liminal.AccountsFixtures.user_fixture()
      scope = Liminal.Accounts.Scope.for_user(user)
      link = link_fixture(scope, %{url: "https://open-disabled.com", title: "Open Disabled"})

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/")

      assert has_element?(view, "#links", "Open Disabled")
      refute has_element?(view, "a[phx-click='open_link'][phx-value-id='#{link.id}']")
    end

    test "anchors carry open_link when preference enabled", %{conn: conn} do
      user = Liminal.AccountsFixtures.user_fixture()
      {:ok, user} = Liminal.Accounts.update_user_settings(user, %{auto_mark_viewed_on_open: true})
      scope = Liminal.Accounts.Scope.for_user(user)
      link = link_fixture(scope, %{url: "https://open-enabled.com", title: "Open Enabled"})

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/")

      assert has_element?(view, "a[phx-click='open_link'][phx-value-id='#{link.id}']")
    end

    test "opening a link marks it viewed when preference enabled", %{conn: conn} do
      user = Liminal.AccountsFixtures.user_fixture()
      {:ok, user} = Liminal.Accounts.update_user_settings(user, %{auto_mark_viewed_on_open: true})
      scope = Liminal.Accounts.Scope.for_user(user)
      link = link_fixture(scope, %{url: "https://open-mark.com", title: "Open Mark"})

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/")

      # Visible in default unviewed filter
      assert has_element?(view, "#links", "Open Mark")

      # Open the link (clicking the title anchor) auto-marks it viewed
      view
      |> element("a[phx-click='open_link'][phx-value-id='#{link.id}']", "Open Mark")
      |> render_click()

      # It leaves the unviewed filter
      refute has_element?(view, "#links", "Open Mark")
      assert Liminal.Links.get_link!(scope, link.id).viewed_at

      # And appears under the viewed filter
      view |> element("button[phx-click='filter'][phx-value-filter='viewed']") |> render_click()
      assert has_element?(view, "#links", "Open Mark")
    end

    test "opening an already-viewed link is a no-op", %{conn: conn} do
      user = Liminal.AccountsFixtures.user_fixture()
      {:ok, user} = Liminal.Accounts.update_user_settings(user, %{auto_mark_viewed_on_open: true})
      scope = Liminal.Accounts.Scope.for_user(user)
      link = link_fixture(scope, %{url: "https://already-viewed.com", title: "Already Viewed"})
      {:ok, _} = Liminal.Links.mark_viewed(scope, link)
      viewed_at = Liminal.Links.get_link!(scope, link.id).viewed_at

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/")

      view |> element("button[phx-click='filter'][phx-value-filter='viewed']") |> render_click()

      view
      |> element("a[phx-click='open_link'][phx-value-id='#{link.id}']", "Already Viewed")
      |> render_click()

      assert Liminal.Links.get_link!(scope, link.id).viewed_at == viewed_at
    end
  end
end
