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
      assert updated.indexed_at != nil
      assert updated.index_attempt_count == 0
      assert is_nil(updated.index_next_attempt_at)
      assert is_nil(updated.index_gave_up_at)
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
      assert updated.index_attempt_count == 1
      assert updated.index_last_attempted_at != nil
      assert updated.index_next_attempt_at != nil
      assert is_nil(updated.index_gave_up_at)
    end

    test "HTTP 500 returns :error and records retry state" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      opts =
        build_req_options(fn conn ->
          Plug.Conn.send_resp(conn, 500, "Internal Server Error")
        end)

      assert :error = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert is_nil(updated.indexed_at)
      assert updated.index_attempt_count == 1
    end

    test "connection error returns :error and records retry state" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      opts =
        build_req_options(fn conn ->
          Req.Test.transport_error(conn, :econnrefused)
        end)

      assert :error = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert is_nil(updated.indexed_at)
      assert updated.index_attempt_count == 1
    end

    test "non-existent link_id returns :error without crashing" do
      scope = user_scope_fixture()
      bogus_id = Ecto.UUID.generate()

      assert :error = Indexer.index(bogus_id, scope.user.id)
    end

    test "successful indexing with og:image downloads and stores image" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      # Set up a temp upload dir for this test
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "liminal_indexer_test_#{System.unique_integer([:positive])}"
        )

      Application.put_env(:liminal, :assets_dir, tmp_dir)

      on_exit(fn ->
        File.rm_rf(tmp_dir)
        Application.delete_env(:liminal, :assets_dir)
      end)

      html_with_image = """
      <html><head>
        <title>Image Page</title>
        <meta property="og:image" content="http://test.local/hero.png">
      </head></html>
      """

      image_bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>

      opts =
        build_req_options(fn conn ->
          case conn.request_path do
            "/hero.png" ->
              conn
              |> Plug.Conn.put_resp_content_type("image/png", nil)
              |> Plug.Conn.send_resp(200, image_bytes)

            _ ->
              html_response(conn, html_with_image)
          end
        end)

      assert :ok = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert updated.image_path != nil
      assert updated.image_path == "assets/#{scope.user.id}/" <> Path.basename(updated.image_path)
      assert updated.title == "Image Page"
    end

    test "indexes video duration for YouTube links" do
      scope = user_scope_fixture()

      link =
        link_fixture(scope, %{
          title: nil,
          url: "https://www.youtube.com/watch?v=abc123"
        })

      html = """
      <html><head>
        <title>YouTube Video</title>
        <meta itemprop="duration" content="PT4M13S">
      </head></html>
      """

      opts =
        build_req_options(fn conn ->
          html_response(conn, html)
        end)

      assert :ok = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert updated.duration_seconds == 253
    end

    test "image download failure still indexes link successfully" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      html_with_image = """
      <html><head>
        <title>Failing Image Page</title>
        <meta property="og:image" content="http://test.local/broken.png">
      </head></html>
      """

      opts =
        build_req_options(fn conn ->
          case conn.request_path do
            "/broken.png" ->
              Plug.Conn.send_resp(conn, 500, "Server Error")

            _ ->
              html_response(conn, html_with_image)
          end
        end)

      assert :ok = Indexer.index(link.id, scope.user.id, opts)

      updated = Links.get_link!(scope, link.id)
      assert updated.title == "Failing Image Page"
      assert updated.indexed_at != nil
      assert is_nil(updated.image_path)
    end
  end
end
