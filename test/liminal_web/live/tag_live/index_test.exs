defmodule LiminalWeb.TagLive.IndexTest do
  use LiminalWeb.ConnCase

  import Phoenix.LiveViewTest
  import Liminal.LinksFixtures

  describe "unauthenticated" do
    test "redirects from /tags", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/tags")
      assert {:redirect, %{to: to}} = redirect
      assert to =~ ~p"/users/register"
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "renders tags list", %{conn: conn, scope: scope} do
      _tag = tag_fixture(scope, %{name: "My Tag"})
      {:ok, view, _html} = live(conn, ~p"/tags")
      assert has_element?(view, "header", "Tags")
      assert has_element?(view, "#tags", "My Tag")
    end

    test "close button stays outside the scrollable modal body", %{conn: conn, scope: scope} do
      for i <- 1..30, do: tag_fixture(scope, %{name: "tag #{i}"})

      {:ok, view, _html} = live(conn, ~p"/tags")

      assert has_element?(view, "#tags-modal-body")
      assert has_element?(view, "#tags-modal-header #tags-modal-close")
      refute has_element?(view, "#tags-modal-body #tags-modal-close")
    end

    test "add a tag via form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tags")

      view |> element("a", "New Tag") |> render_click()
      assert has_element?(view, "#tag-form")

      view
      |> form("#tag-form", tag: %{name: "New Tag", expires_in_days: 7})
      |> render_submit()

      assert has_element?(view, "#tags", "New Tag")
    end

    test "edit a tag", %{conn: conn, scope: scope} do
      tag = tag_fixture(scope, %{name: "Edit Me"})
      {:ok, view, _html} = live(conn, ~p"/tags")

      view |> element("a[href='/tags/#{tag.id}/edit']") |> render_click()
      assert has_element?(view, "#tag-form")

      view
      |> form("#tag-form", tag: %{name: "Edited"})
      |> render_submit()

      assert has_element?(view, "#tags", "Edited")
    end

    test "delete a tag", %{conn: conn, scope: scope} do
      tag = tag_fixture(scope, %{name: "Delete Me"})
      {:ok, view, _html} = live(conn, ~p"/tags")

      assert has_element?(view, "#tags", "Delete Me")

      view
      |> element("button[phx-click='delete'][phx-value-id='#{tag.id}']")
      |> render_click()

      refute has_element?(view, "#tags", "Delete Me")
    end
  end
end
