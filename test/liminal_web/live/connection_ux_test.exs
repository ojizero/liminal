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

      assert [tag] = Regex.run(~r/<div[^>]*id="lv-connecting"[^>]*>/, html)
      assert tag =~ ~s(id="lv-connecting")
      assert tag =~ "phx-connected="
      # Visible on first paint: no HTML hidden attribute on the opening tag.
      # (phx-connected payload may mention "hidden" as a JS command.)
      refute tag =~ ~r/(?:^|\s)hidden(?:\s|=|>|$)/
      assert html =~ "Establishing live connection"
      assert html =~ "Connecting"
    end

    test "connected markup keeps reconnect toasts and connecting binding", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # LiveViewTest does not execute client JS commands; assert bindings stay in place.
      assert has_element?(view, "#lv-connecting")
      assert has_element?(view, "#client-error[hidden]")
      assert has_element?(view, "#server-error[hidden]")
      assert has_element?(view, "#flash-group")
      assert has_element?(view, "#connection-restored[hidden]")

      html = render(view)
      assert [tag] = Regex.run(~r/<div[^>]*id="lv-connecting"[^>]*>/, html)
      assert tag =~ "phx-connected="
    end
  end
end
