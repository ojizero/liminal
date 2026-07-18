defmodule Liminal.Links.OEmbed do
  @moduledoc """
  Fetches video metadata via the oEmbed protocol.

  Uses oEmbed discovery tags from HTML when available, then falls back to
  known provider endpoints for common video hosts.
  """

  require Logger

  @default_req_options [
    max_redirects: 5,
    receive_timeout: 10_000,
    retry: false,
    headers: [{"user-agent", "Liminal/1.0 (link indexer)"}]
  ]

  @known_endpoints %{
    youtube: "https://www.youtube.com/oembed",
    vimeo: "https://vimeo.com/api/oembed.json"
  }

  @doc """
  Returns duration in seconds from oEmbed when available.

  `html` is optional page HTML used for oEmbed endpoint discovery.
  """
  @spec fetch_duration(String.t(), String.t() | nil, keyword()) :: non_neg_integer() | nil
  def fetch_duration(url, html \\ nil, opts \\ []) do
    with endpoint when is_binary(endpoint) <- discover_or_known_endpoint(url, html),
         {:ok, data} <- fetch_oembed(endpoint, url, opts),
         duration when is_integer(duration) <- parse_duration(data) do
      duration
    else
      _ -> nil
    end
  end

  @doc """
  Discovers an oEmbed endpoint from HTML link tags.
  """
  @spec discover_endpoint(String.t(), String.t()) :: String.t() | nil
  def discover_endpoint(html, page_url) when is_binary(html) and html != "" do
    oembed_link_pattern()
    |> Regex.run(html)
    |> endpoint_from_match(page_url)
  end

  def discover_endpoint(_html, _page_url), do: nil

  defp discover_or_known_endpoint(url, html) do
    discover_endpoint(html || "", url) || known_endpoint(url)
  end

  defp oembed_link_pattern do
    ~r/<link\s+(?=[^>]*\brel\s*=\s*["']alternate["'])(?=[^>]*\btype\s*=\s*["']application\/json\+oembed["'])(?=[^>]*\bhref\s*=\s*["']([^"']+)["'])[^>]*\/?>/si
  end

  defp endpoint_from_match([_, href], page_url), do: resolve_url(href, page_url)
  defp endpoint_from_match(_, _page_url), do: nil

  defp known_endpoint(url) do
    case video_provider(url) do
      :youtube -> @known_endpoints.youtube
      :vimeo -> @known_endpoints.vimeo
      _ -> nil
    end
  end

  defp fetch_oembed(endpoint, url, opts) do
    req_options =
      @default_req_options
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    case Req.get(endpoint, Keyword.merge(req_options, params: [url: url, format: "json"])) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, data} when is_map(data) -> {:ok, data}
          _ -> :error
        end

      {:ok, %{status: status}} ->
        Logger.debug("OEmbed: non-200 status #{status} for #{url}")
        :error

      {:error, reason} ->
        Logger.debug("OEmbed: request failed for #{url}: #{inspect(reason)}")
        :error
    end
  end

  defp parse_duration(%{"duration" => duration}) when is_integer(duration) and duration > 0 do
    duration
  end

  defp parse_duration(%{"duration" => duration}) when is_binary(duration) do
    case Integer.parse(duration) do
      {seconds, ""} when seconds > 0 -> seconds
      _ -> nil
    end
  end

  defp parse_duration(_), do: nil

  defp video_provider(url) do
    uri = URI.parse(url)

    cond do
      host_matches?(uri.host, ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"]) ->
        :youtube

      host_matches?(uri.host, ["vimeo.com", "www.vimeo.com", "player.vimeo.com"]) ->
        :vimeo

      true ->
        nil
    end
  end

  defp host_matches?(host, candidates) when is_binary(host) do
    host in candidates or String.ends_with?(host, ".vimeo.com")
  end

  defp host_matches?(_, _), do: false

  defp resolve_url(href, base_url) do
    URI.merge(base_url, href) |> to_string()
  rescue
    _ -> nil
  end
end
