defmodule Liminal.Links.OEmbedTest do
  use ExUnit.Case, async: true

  alias Liminal.Links.OEmbed

  defp build_req_options(plug_fn) do
    [req_options: [plug: plug_fn]]
  end

  defp json_response(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  describe "discover_endpoint/2" do
    test "finds oEmbed discovery link in HTML" do
      html = ~s(
        <link rel="alternate" type="application/json+oembed"
              href="https://vimeo.com/api/oembed.json?url=https%3A%2F%2Fvimeo.com%2F123">
      )

      assert OEmbed.discover_endpoint(html, "https://vimeo.com/123") ==
               "https://vimeo.com/api/oembed.json?url=https%3A%2F%2Fvimeo.com%2F123"
    end
  end

  describe "fetch_duration/3" do
    test "returns duration from Vimeo oEmbed endpoint" do
      opts =
        build_req_options(fn conn ->
          json_response(conn, %{
            "type" => "video",
            "duration" => 822,
            "title" => "Example"
          })
        end)

      assert OEmbed.fetch_duration("https://vimeo.com/7806742", nil, opts) == 822
    end

    test "returns nil when oEmbed response has no duration" do
      opts =
        build_req_options(fn conn ->
          json_response(conn, %{
            "type" => "video",
            "title" => "Example"
          })
        end)

      assert OEmbed.fetch_duration("https://www.youtube.com/watch?v=abc123", nil, opts) == nil
    end
  end
end
