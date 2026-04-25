defmodule Liminal.Links.IndexerTest do
  use Liminal.DataCase

  import Liminal.AccountsFixtures
  import Liminal.LinksFixtures

  alias Liminal.Links
  alias Liminal.Links.Indexer

  defp build_req_options(plug_fn) do
    [req_options: [plug: plug_fn]]
  end

  defp html_response(conn, html) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, html)
  end

  @sample_html """
  <html><head>
    <title>Example Page</title>
    <meta name="description" content="A test page">
    <link rel="icon" href="/favicon.png">
  </head></html>
  """

  describe "index/3" do
    test "successful indexing populates metadata and sets indexed_at" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      opts =
        build_req_options(fn conn ->
          html_response(conn, @sample_html)
        end)

      assert :ok = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert updated.title == "Example Page"
      assert updated.description == "A test page"
      assert updated.indexed_at != nil
    end

    test "broadcasts :link_updated after successful indexing" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      Links.subscribe_links(scope)

      opts =
        build_req_options(fn conn ->
          html_response(conn, @sample_html)
        end)

      assert :ok = Indexer.index(link.id, scope.user.id, opts)

      assert_receive {:link_updated, broadcast_link}
      assert broadcast_link.id == link.id
      assert broadcast_link.title == "Example Page"
      assert Ecto.assoc_loaded?(broadcast_link.link_tags)
    end

    test "does not overwrite user-provided title" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: "My Custom Title"})

      html = """
      <html><head>
        <title>Indexed Title</title>
        <meta name="description" content="Indexed description">
      </head></html>
      """

      opts =
        build_req_options(fn conn ->
          html_response(conn, html)
        end)

      assert :ok = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert updated.title == "My Custom Title"
      assert updated.description == "Indexed description"
      assert updated.indexed_at != nil
    end

    test "HTTP 404 returns :error and does not set indexed_at" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      opts =
        build_req_options(fn conn ->
          Plug.Conn.send_resp(conn, 404, "Not Found")
        end)

      assert :error = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert is_nil(updated.indexed_at)
    end

    test "HTTP 500 returns :error and does not set indexed_at" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      opts =
        build_req_options(fn conn ->
          Plug.Conn.send_resp(conn, 500, "Internal Server Error")
        end)

      assert :error = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert is_nil(updated.indexed_at)
    end

    test "connection error returns :error and does not set indexed_at" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      opts =
        build_req_options(fn conn ->
          Req.Test.transport_error(conn, :econnrefused)
        end)

      assert :error = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert is_nil(updated.indexed_at)
    end

    test "non-existent link_id returns :error without crashing" do
      scope = user_scope_fixture()
      bogus_id = Ecto.UUID.generate()

      assert :error = Indexer.index(bogus_id, scope.user.id)
    end
  end
end
