defmodule Liminal.Links.MetadataParser do
  @moduledoc """
  Extracts metadata (title, description, favicon URL, image URL) from raw HTML using regex.

  This module is pure -- no side effects, no HTTP calls.
  """

  @type metadata :: %{
          title: String.t() | nil,
          description: String.t() | nil,
          favicon_url: String.t() | nil,
          image_url: String.t() | nil
        }

  @doc """
  Parses HTML and returns a map with extracted title, description, favicon URL, and image URL.

  The `base_url` is used to resolve relative favicon URLs to absolute ones.
  """
  @spec parse(String.t() | nil, String.t()) :: metadata()
  def parse(html, base_url) when is_binary(html) and html != "" do
    %{
      title: extract_title(html),
      description: extract_description(html),
      favicon_url: extract_favicon(html, base_url),
      image_url: extract_image(html, base_url)
    }
  end

  def parse(_html, _base_url) do
    %{title: nil, description: nil, favicon_url: nil, image_url: nil}
  end

  # Title extraction: OG title first, then <title> tag fallback

  defp extract_title(html) do
    extract_og_meta(html, "og:title") || extract_title_tag(html)
  end

  defp extract_title_tag(html) do
    case Regex.run(~r/<title[^>]*>(.*?)<\/title>/si, html) do
      [_, content] -> normalize_text(content)
      _ -> nil
    end
  end

  # Description extraction: OG description first, then meta name="description" fallback

  defp extract_description(html) do
    extract_og_meta(html, "og:description") ||
      extract_meta_name(html, "description") ||
      extract_meta_name(html, "twitter:description")
  end

  # Image extraction: OG image first, then twitter:image fallback

  defp extract_image(html, base_url) do
    raw_url = extract_og_meta(html, "og:image") || extract_meta_name(html, "twitter:image")
    if raw_url, do: resolve_url(raw_url, base_url), else: nil
  end

  # Favicon extraction: explicit <link rel="icon"> or <link rel="shortcut icon">, then /favicon.ico fallback

  defp extract_favicon(html, base_url) do
    href = extract_favicon_link(html)

    if href do
      resolve_url(href, base_url)
    else
      fallback_favicon(base_url)
    end
  end

  defp extract_favicon_link(html) do
    # Match <link> tags with rel="icon" or rel="shortcut icon", in either attribute order
    pattern =
      ~r/<link\s+(?=[^>]*\brel\s*=\s*["'](?:shortcut\s+)?icon["'])(?=[^>]*\bhref\s*=\s*["']([^"']+)["'])[^>]*\/?>/si

    case Regex.run(pattern, html) do
      [_, href] ->
        href

      _ ->
        # Try alternate ordering: href before rel
        alt_pattern =
          ~r/<link\s+(?=[^>]*\bhref\s*=\s*["']([^"']+)["'])(?=[^>]*\brel\s*=\s*["'](?:shortcut\s+)?icon["'])[^>]*\/?>/si

        case Regex.run(alt_pattern, html) do
          [_, href] -> href
          _ -> nil
        end
    end
  end

  defp fallback_favicon(base_url) do
    resolve_url("/favicon.ico", base_url)
  end

  defp resolve_url(href, base_url) do
    URI.merge(base_url, href) |> to_string()
  rescue
    _ -> nil
  end

  # Shared helpers for extracting OG meta tags and name-based meta tags

  defp extract_og_meta(html, property) do
    # property="og:..." content="..."
    pattern_a =
      ~r/<meta\s+(?=[^>]*\bproperty\s*=\s*["']#{Regex.escape(property)}["'])(?=[^>]*\bcontent\s*=\s*["']([^"']*?)["'])[^>]*\/?>/si

    case Regex.run(pattern_a, html) do
      [_, content] ->
        normalize_text(content)

      _ ->
        # content="..." property="og:..."
        pattern_b =
          ~r/<meta\s+(?=[^>]*\bcontent\s*=\s*["']([^"']*?)["'])(?=[^>]*\bproperty\s*=\s*["']#{Regex.escape(property)}["'])[^>]*\/?>/si

        case Regex.run(pattern_b, html) do
          [_, content] -> normalize_text(content)
          _ -> nil
        end
    end
  end

  defp extract_meta_name(html, name) do
    # name="..." content="..."
    pattern_a =
      ~r/<meta\s+(?=[^>]*\bname\s*=\s*["']#{Regex.escape(name)}["'])(?=[^>]*\bcontent\s*=\s*["']([^"']*?)["'])[^>]*\/?>/si

    case Regex.run(pattern_a, html) do
      [_, content] ->
        normalize_text(content)

      _ ->
        # content="..." name="..."
        pattern_b =
          ~r/<meta\s+(?=[^>]*\bcontent\s*=\s*["']([^"']*?)["'])(?=[^>]*\bname\s*=\s*["']#{Regex.escape(name)}["'])[^>]*\/?>/si

        case Regex.run(pattern_b, html) do
          [_, content] -> normalize_text(content)
          _ -> nil
        end
    end
  end

  # Text normalization: decode HTML entities, trim whitespace, return nil if empty

  defp normalize_text(text) do
    result =
      text
      |> decode_entities()
      |> String.trim()

    if result == "", do: nil, else: result
  end

  defp decode_entities(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end
end
