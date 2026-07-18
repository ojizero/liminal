defmodule Liminal.Links.Indexer do
  @moduledoc """
  Fetches URL metadata for a link and updates the database.

  Designed to run as a fire-and-forget Task under `Liminal.Links.IndexerTaskSupervisor`.
  Accepts `:req_options` via opts for test injection.
  """

  require Logger

  @default_req_options [
    max_redirects: 5,
    receive_timeout: 10_000,
    retry: false,
    headers: [{"user-agent", "Liminal/1.0 (link indexer)"}]
  ]

  @doc """
  Fetches the HTML at the link's URL, parses metadata, and persists it.

  Returns `:ok` on success, `:error` on failure. Failed links record retry
  state via `Indexing.record_index_failure/1` for the Janitor to retry with backoff.

  ## Options

    * `:req_options` - additional options merged into the Req request
      (useful for test injection via `Req.Test`)

  """

  alias Liminal.Links.Indexing

  def index(link_id, user_id, opts \\ []) do
    case Liminal.Repo.get(Liminal.Links.Link, link_id) do
      nil ->
        :error

      %{user_id: ^user_id} = link ->
        index_link(link, opts)

      _link ->
        Logger.warning("Indexer: user_id mismatch for link #{link_id}")
        :error
    end
  end

  defp index_link(link, opts) do
    req_options =
      Keyword.merge(@default_req_options, Keyword.get(opts, :req_options, []))

    case Req.get(link.url, req_options) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        metadata = Liminal.Links.MetadataParser.parse(body, link.url)

        # Clean up previously stored image (e.g., during re-indexing)
        if link.image_path do
          Liminal.Links.ImageDownloader.delete(link.image_path)
        end

        image_path =
          if metadata[:image_url] do
            case Liminal.Links.ImageDownloader.download_and_store(
                   metadata.image_url,
                   link.user_id,
                   opts
                 ) do
              {:ok, path} ->
                path

              {:error, reason} ->
                Logger.warning(
                  "Indexer: image download failed for #{link.id}: #{inspect(reason)}"
                )

                nil
            end
          end

        duration_seconds =
          Liminal.Links.VideoMetadata.fetch_duration(link.url, body, opts)

        metadata =
          metadata
          |> Map.delete(:image_url)
          |> Map.put(:image_path, image_path)
          |> Map.put(:duration_seconds, duration_seconds)

        Indexing.update_link_metadata(link, metadata)
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("Indexer: non-200 status #{status} for link #{link.id} (#{link.url})")
        Indexing.record_index_failure(link)
        :error

      {:error, reason} ->
        Logger.warning(
          "Indexer: request failed for link #{link.id} (#{link.url}): #{inspect(reason)}"
        )

        Indexing.record_index_failure(link)
        :error
    end
  end
end
