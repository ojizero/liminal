defmodule Liminal.Links.MetadataParser do
  @moduledoc """
  Extracts page metadata from raw HTML via regex — kept separate from HTTP so
  parsing stays pure and testable without network calls.
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
  def parse(nil, _base_url), do: empty_metadata()

  def parse("", _base_url), do: empty_metadata()

  def parse(html, base_url) when is_binary(html) do
    %{
      title: extract_title(html),
      description: extract_description(html),
      favicon_url: extract_favicon(html, base_url),
      image_url: extract_image(html, base_url)
    }
  end

  def parse(_html, _base_url) do
    empty_metadata()
  end

  @favicon_link_pattern ~r/<link\s+(?=[^>]*\brel\s*=\s*["'](?:shortcut\s+)?icon["'])(?=[^>]*\bhref\s*=\s*["']([^"']+)["'])[^>]*\/?>/si

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
    resolve_optional_url(raw_url, base_url)
  end

  # Favicon extraction: explicit <link rel="icon"> or <link rel="shortcut icon">, then /favicon.ico fallback

  defp extract_favicon(html, base_url) do
    href = extract_favicon_link(html)
    resolve_favicon_url(href, base_url)
  end

  defp extract_favicon_link(html) do
    @favicon_link_pattern
    |> Regex.run(html)
    |> captured_value()
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
    extract_meta_content(html, "property", property)
  end

  defp extract_meta_name(html, name) do
    extract_meta_content(html, "name", name)
  end

  defp extract_meta_content(html, attr_name, attr_value) do
    attr_value = Regex.escape(attr_value)

    pattern_source =
      "<meta\\s+(?=[^>]*\\b#{attr_name}\\s*=\\s*[\"']#{attr_value}[\"'])(?=[^>]*\\bcontent\\s*=\\s*[\"']([^\"']*?)[\"'])[^>]*\\/?>"

    pattern = Regex.compile!(pattern_source, "si")

    pattern
    |> Regex.run(html)
    |> captured_value()
    |> normalize_text()
  end

  # Text normalization: decode HTML entities, trim whitespace, return nil if empty

  defp normalize_text(nil), do: nil

  defp normalize_text(text) do
    result =
      text
      |> decode_entities()
      |> String.trim()

    empty_string_to_nil(result)
  end

  defp captured_value([_, value]), do: value
  defp captured_value(_), do: nil

  defp resolve_optional_url(nil, _base_url), do: nil
  defp resolve_optional_url(raw_url, base_url), do: resolve_url(raw_url, base_url)

  defp resolve_favicon_url(nil, base_url), do: fallback_favicon(base_url)
  defp resolve_favicon_url(href, base_url), do: resolve_url(href, base_url)

  defp empty_string_to_nil(""), do: nil
  defp empty_string_to_nil(value), do: value

  defp empty_metadata do
    %{title: nil, description: nil, favicon_url: nil, image_url: nil}
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
