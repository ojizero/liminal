defmodule LiminalWeb.CategoryLive.IndexTest do
  use LiminalWeb.ConnCase

  import Phoenix.LiveViewTest
  import Liminal.LinksFixtures

  describe "unauthenticated" do
    test "redirects from /categories", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/categories")
      assert {:redirect, %{to: to}} = redirect
      assert to =~ ~p"/users/log-in"
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "renders categories list", %{conn: conn, scope: scope} do
      _category = category_fixture(scope, %{name: "My Category"})
      {:ok, view, _html} = live(conn, ~p"/categories")
      assert has_element?(view, "header", "Categories")
      assert has_element?(view, "#categories", "My Category")
    end

    test "add a category via form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/categories")

      view |> element("a", "New Category") |> render_click()
      assert has_element?(view, "#category-form")

      view
      |> form("#category-form", category: %{name: "New Cat", expires_in_days: 7})
      |> render_submit()

      assert has_element?(view, "#categories", "New Cat")
    end

    test "edit a category", %{conn: conn, scope: scope} do
      category = category_fixture(scope, %{name: "Edit Me"})
      {:ok, view, _html} = live(conn, ~p"/categories")

      view |> element("a[href='/categories/#{category.id}/edit']") |> render_click()
      assert has_element?(view, "#category-form")

      view
      |> form("#category-form", category: %{name: "Edited"})
      |> render_submit()

      assert has_element?(view, "#categories", "Edited")
    end

    test "delete a category", %{conn: conn, scope: scope} do
      category = category_fixture(scope, %{name: "Delete Me"})
      {:ok, view, _html} = live(conn, ~p"/categories")

      assert has_element?(view, "#categories", "Delete Me")

      view
      |> element("button[phx-click='delete'][phx-value-id='#{category.id}']")
      |> render_click()

      refute has_element?(view, "#categories", "Delete Me")
    end
  end
end
