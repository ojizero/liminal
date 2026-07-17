defmodule LiminalWeb.ConnectionUXTest do
  use LiminalWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "initial connecting indicator" do
    setup :register_and_log_in_user

    test "dead render includes connecting toast before LiveView joins", %{conn: conn} do
      html =
        conn
        |> get(~p"/")
        |> html_response(200)

      assert html =~ ~s(id="lv-connecting")
      assert html =~ "Establishing live connection"
      # Must be visible on first paint (no hidden attribute on the toast root).
      refute html =~ ~r/id="lv-connecting"[^>]*\bhidden\b/
    end

    test "connected render hides connecting toast via phx-connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#lv-connecting[hidden]")
      assert has_element?(view, "#client-error[hidden]")
      assert has_element?(view, "#server-error[hidden]")
    end

    test "reconnect toasts remain available after connect", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#flash-group")
      assert has_element?(view, "#client-error-retry.hidden")
      assert has_element?(view, "#connection-restored[hidden]")
    end
  end
end
