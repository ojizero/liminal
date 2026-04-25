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

  Returns `:ok` on success, `:error` on failure. Failed links are left
  without `indexed_at` so the Janitor can retry them later.

  ## Options

    * `:req_options` - additional options merged into the Req request
      (useful for test injection via `Req.Test`)

  """
  def index(link_id, _user_id, opts \\ []) do
    case Liminal.Repo.get(Liminal.Links.Link, link_id) do
      nil ->
        :error

      link ->
        req_options =
          Keyword.merge(@default_req_options, Keyword.get(opts, :req_options, []))

        case Req.get(link.url, req_options) do
          {:ok, %{status: 200, body: body}} when is_binary(body) ->
            metadata = Liminal.Links.MetadataParser.parse(body, link.url)
            Liminal.Links.update_link_metadata(link, metadata)
            :ok

          {:ok, %{status: status}} ->
            Logger.warning("Indexer: non-200 status #{status} for link #{link_id} (#{link.url})")
            :error

          {:error, reason} ->
            Logger.warning(
              "Indexer: request failed for link #{link_id} (#{link.url}): #{inspect(reason)}"
            )

            :error
        end
    end
  end
end
