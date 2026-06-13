defmodule Liminal.Links.VideoMetadata do
  @moduledoc """
  Extracts video duration from indexed pages.

  Tries oEmbed first (works for Vimeo and other providers that expose duration),
  then falls back to provider-specific HTML parsing (e.g. YouTube).
  """

  alias Liminal.Links.{Duration, OEmbed}

  @length_seconds_pattern ~r/"lengthSeconds"\s*:\s*"?(\d+)"?/
  @approx_duration_ms_pattern ~r/"approxDurationMs"\s*:\s*"?(\d+)"?/
  @itemprop_duration_pattern ~r/<meta\s+[^>]*itemprop\s*=\s*["']duration["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*\/?>/i
  @itemprop_duration_alt_pattern ~r/<meta\s+[^>]*content\s*=\s*["']([^"']+)["'][^>]*itemprop\s*=\s*["']duration["'][^>]*\/?>/i

  @doc """
  Returns video duration in seconds when the URL or HTML indicates a video.
  """
  @spec fetch_duration(String.t(), String.t() | nil, keyword()) :: non_neg_integer() | nil
  def fetch_duration(url, html \\ nil, opts \\ []) do
    if video_url?(url) do
      oembed_duration(url, html, opts) || html_duration(url, html)
    end
  end

  @doc false
  def video_url?(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      host_matches?(uri.host, ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"]) ->
        youtube_video_path?(uri)

      host_matches?(uri.host, ["vimeo.com", "www.vimeo.com"]) ->
        String.match?(uri.path || "", ~r{^/\d+})

      is_binary(uri.host) and String.ends_with?(uri.host, ".vimeo.com") ->
        String.match?(uri.path || "", ~r{^/video/\d+})

      true ->
        false
    end
  end

  def video_url?(_), do: false

  defp oembed_duration(url, html, opts) do
    OEmbed.fetch_duration(url, html, opts)
  end

  defp html_duration(url, html) when is_binary(html) and html != "" do
    case video_provider(url) do
      :youtube -> parse_youtube_duration(html)
      _ -> parse_generic_duration(html)
    end
  end

  defp html_duration(_url, _html), do: nil

  defp parse_youtube_duration(html) do
    parse_generic_duration(html) ||
      parse_length_seconds(html) ||
      parse_approx_duration_ms(html)
  end

  defp parse_generic_duration(html) do
    case Regex.run(@itemprop_duration_pattern, html) do
      [_, value] -> Duration.parse_iso8601(value)
      _ -> nil
    end
    |> case do
      nil ->
        case Regex.run(@itemprop_duration_alt_pattern, html) do
          [_, value] -> Duration.parse_iso8601(value)
          _ -> nil
        end

      duration ->
        duration
    end
  end

  defp parse_length_seconds(html) do
    case Regex.run(@length_seconds_pattern, html) do
      [_, value] ->
        case Integer.parse(value) do
          {seconds, ""} when seconds > 0 -> seconds
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_approx_duration_ms(html) do
    case Regex.run(@approx_duration_ms_pattern, html) do
      [_, value] ->
        case Integer.parse(value) do
          {ms, ""} when ms > 0 -> div(ms, 1000)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp video_provider(url) do
    uri = URI.parse(url)

    cond do
      host_matches?(uri.host, ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"]) ->
        :youtube

      host_matches?(uri.host, ["vimeo.com", "www.vimeo.com"]) or
          (is_binary(uri.host) and String.ends_with?(uri.host, ".vimeo.com")) ->
        :vimeo

      true ->
        nil
    end
  end

  defp youtube_video_path?(%URI{host: "youtu.be", path: "/" <> id}) when byte_size(id) > 0,
    do: true

  defp youtube_video_path?(%URI{path: path}) when is_binary(path) do
    String.match?(path, ~r{^/watch}) or String.match?(path, ~r{^/shorts/}) or
      String.match?(path, ~r{^/embed/}) or String.match?(path, ~r{^/live/})
  end

  defp youtube_video_path?(_), do: false

  defp host_matches?(host, candidates) when is_binary(host) and is_list(candidates),
    do: host in candidates

  defp host_matches?(_, _), do: false
end
