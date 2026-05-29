defmodule Liminal.Links.ImageDownloader do
  require Logger

  @max_image_size 5 * 1024 * 1024
  @allowed_content_types ~w(image/jpeg image/png image/gif image/webp image/svg+xml)

  @req_options [
    max_redirects: 5,
    receive_timeout: 15_000,
    retry: false,
    headers: [{"user-agent", "Liminal/1.0 (link indexer)"}],
    decode_body: false
  ]

  def download_and_store(url, opts \\ []) do
    req_options = Keyword.merge(@req_options, Keyword.get(opts, :req_options, []))

    with {:ok, %{status: 200, headers: headers, body: body}} <- Req.get(url, req_options),
         :ok <- validate_content_type(headers),
         :ok <- validate_size(body) do
      extension = extension_from_headers(headers) || extension_from_url(url) || ".jpg"
      filename = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false) <> extension
      dest_dir = assets_dir()
      File.mkdir_p!(dest_dir)
      File.write!(Path.join(dest_dir, filename), body)
      {:ok, Liminal.AssetPaths.relative_path(filename)}
    else
      {:ok, %{status: _}} -> {:error, :bad_status}
      {:error, _} = err -> err
    end
  end

  def delete(nil), do: :ok

  def delete(image_path) do
    full_path = Liminal.AssetPaths.file_path(image_path)

    case File.rm(full_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  defp assets_dir, do: Liminal.AssetPaths.assets_dir()

  defp validate_content_type(headers) do
    content_type = get_content_type(headers)

    if content_type && Enum.any?(@allowed_content_types, &String.starts_with?(content_type, &1)) do
      :ok
    else
      {:error, :invalid_content_type}
    end
  end

  defp validate_size(body) when byte_size(body) <= @max_image_size, do: :ok
  defp validate_size(_body), do: {:error, :too_large}

  defp extension_from_headers(headers) do
    case get_content_type(headers) do
      "image/jpeg" <> _ -> ".jpg"
      "image/png" <> _ -> ".png"
      "image/gif" <> _ -> ".gif"
      "image/webp" <> _ -> ".webp"
      "image/svg+xml" <> _ -> ".svg"
      _ -> nil
    end
  end

  defp get_content_type(headers) do
    Enum.find_value(headers, fn
      {key, [value | _]} when is_binary(key) ->
        if String.downcase(key) == "content-type", do: value

      {key, value} when is_binary(key) and is_binary(value) ->
        if String.downcase(key) == "content-type", do: value

      _ ->
        nil
    end)
  end

  defp extension_from_url(url) do
    path = URI.parse(url).path || ""

    case Path.extname(path) do
      "." <> _ = ext when ext in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"] -> ext
      _ -> nil
    end
  end
end
