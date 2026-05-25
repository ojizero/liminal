defmodule Liminal.Links.ImageDownloaderTest do
  use Liminal.DataCase

  alias Liminal.Links.ImageDownloader

  @image_bytes <<137, 80, 78, 71, 13, 10, 26, 10>>

  defp image_plug(conn, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, "image/png")
    body = Keyword.get(opts, :body, @image_bytes)
    status = Keyword.get(opts, :status, 200)

    conn
    |> Plug.Conn.put_resp_content_type(content_type, nil)
    |> Plug.Conn.send_resp(status, body)
  end

  defp build_opts(plug_fn) do
    [req_options: [plug: plug_fn]]
  end

  setup do
    # Use a temp directory for uploads during tests
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "liminal_test_uploads_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:liminal, :upload_dir, tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
      Application.delete_env(:liminal, :upload_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "download_and_store/2" do
    test "downloads and stores image from valid URL", %{tmp_dir: tmp_dir} do
      opts = build_opts(fn conn -> image_plug(conn) end)

      assert {:ok, path} =
               ImageDownloader.download_and_store("http://example.com/image.png", opts)

      assert String.starts_with?(path, "uploads/images/")
      assert String.ends_with?(path, ".png")

      # Verify file exists on disk
      filename = Path.basename(path)
      assert File.exists?(Path.join(tmp_dir, filename))
    end

    test "returns error for non-200 responses" do
      opts = build_opts(fn conn -> Plug.Conn.send_resp(conn, 404, "Not Found") end)

      assert {:error, :bad_status} =
               ImageDownloader.download_and_store("http://example.com/missing.png", opts)
    end

    test "returns error for non-image content types" do
      opts =
        build_opts(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/html")
          |> Plug.Conn.send_resp(200, "<html></html>")
        end)

      assert {:error, :invalid_content_type} =
               ImageDownloader.download_and_store("http://example.com/page.html", opts)
    end

    test "returns error for images exceeding 5MB" do
      large_body = :binary.copy(<<0>>, 6 * 1024 * 1024)
      opts = build_opts(fn conn -> image_plug(conn, body: large_body) end)

      assert {:error, :too_large} =
               ImageDownloader.download_and_store("http://example.com/huge.png", opts)
    end

    test "determines extension from content-type header" do
      opts = build_opts(fn conn -> image_plug(conn, content_type: "image/jpeg") end)
      assert {:ok, path} = ImageDownloader.download_and_store("http://example.com/photo", opts)
      assert String.ends_with?(path, ".jpg")
    end

    test "falls back to URL extension when content-type has no match" do
      opts =
        build_opts(fn conn -> image_plug(conn, content_type: "application/octet-stream") end)

      # application/octet-stream isn't in the allowed content types
      assert {:error, :invalid_content_type} =
               ImageDownloader.download_and_store("http://example.com/photo.webp", opts)
    end

    test "falls back to .jpg when no extension can be determined" do
      opts = build_opts(fn conn -> image_plug(conn, content_type: "image/jpeg") end)
      assert {:ok, path} = ImageDownloader.download_and_store("http://example.com/photo", opts)
      assert String.ends_with?(path, ".jpg")
    end
  end

  describe "delete/1" do
    test "removes file from disk", %{tmp_dir: tmp_dir} do
      opts = build_opts(fn conn -> image_plug(conn) end)
      {:ok, path} = ImageDownloader.download_and_store("http://example.com/img.png", opts)

      filename = Path.basename(path)
      assert File.exists?(Path.join(tmp_dir, filename))

      assert :ok = ImageDownloader.delete(path)
      refute File.exists?(Path.join(tmp_dir, filename))
    end

    test "returns :ok for nil" do
      assert :ok = ImageDownloader.delete(nil)
    end

    test "returns :ok for non-existent file" do
      assert :ok = ImageDownloader.delete("uploads/images/nonexistent.jpg")
    end
  end
end
