defmodule Liminal.Links.MetadataParserTest do
  use Liminal.DataCase

  alias Liminal.Links.MetadataParser

  @base_url "https://example.com"

  describe "title extraction" do
    test "extracts title from og:title meta tag" do
      html = """
      <html><head>
        <meta property="og:title" content="OG Title">
      </head></html>
      """

      assert %{title: "OG Title"} = MetadataParser.parse(html, @base_url)
    end

    test "falls back to <title> tag when no og:title" do
      html = """
      <html><head>
        <title>My Title</title>
      </head></html>
      """

      assert %{title: "My Title"} = MetadataParser.parse(html, @base_url)
    end

    test "og:title takes priority over <title> tag" do
      html = """
      <html><head>
        <meta property="og:title" content="OG Title">
        <title>Fallback Title</title>
      </head></html>
      """

      assert %{title: "OG Title"} = MetadataParser.parse(html, @base_url)
    end

    test "returns nil title when neither og:title nor <title> present" do
      html = """
      <html><head>
        <meta name="description" content="no title here">
      </head></html>
      """

      assert %{title: nil} = MetadataParser.parse(html, @base_url)
    end
  end

  describe "description extraction" do
    test "extracts description from og:description meta tag" do
      html = """
      <html><head>
        <meta property="og:description" content="OG Description">
      </head></html>
      """

      assert %{description: "OG Description"} = MetadataParser.parse(html, @base_url)
    end

    test "falls back to meta name=description when no og:description" do
      html = """
      <html><head>
        <meta name="description" content="Meta Description">
      </head></html>
      """

      assert %{description: "Meta Description"} = MetadataParser.parse(html, @base_url)
    end

    test "og:description takes priority over meta name=description" do
      html = """
      <html><head>
        <meta property="og:description" content="OG Description">
        <meta name="description" content="Fallback Description">
      </head></html>
      """

      assert %{description: "OG Description"} = MetadataParser.parse(html, @base_url)
    end

    test "returns nil description when no description meta tags present" do
      html = """
      <html><head>
        <title>No description</title>
      </head></html>
      """

      assert %{description: nil} = MetadataParser.parse(html, @base_url)
    end
  end

  describe "favicon extraction" do
    test "extracts favicon from link rel=icon with absolute URL" do
      html = """
      <html><head>
        <link rel="icon" href="https://cdn.example.com/favicon.png">
      </head></html>
      """

      assert %{favicon_url: "https://cdn.example.com/favicon.png"} =
               MetadataParser.parse(html, @base_url)
    end

    test "extracts favicon from link rel=shortcut icon" do
      html = """
      <html><head>
        <link rel="shortcut icon" href="https://example.com/icon.ico">
      </head></html>
      """

      assert %{favicon_url: "https://example.com/icon.ico"} =
               MetadataParser.parse(html, @base_url)
    end

    test "resolves relative favicon URL against base_url" do
      html = """
      <html><head>
        <link rel="icon" href="/img/fav.png">
      </head></html>
      """

      assert %{favicon_url: "https://example.com/img/fav.png"} =
               MetadataParser.parse(html, @base_url)
    end

    test "falls back to /favicon.ico when no explicit icon link" do
      html = """
      <html><head>
        <title>No favicon link</title>
      </head></html>
      """

      assert %{favicon_url: "https://example.com/favicon.ico"} =
               MetadataParser.parse(html, @base_url)
    end
  end

  describe "reversed attribute ordering" do
    test "handles content before property in og meta tags" do
      html = """
      <html><head>
        <meta content="Reversed OG Title" property="og:title">
      </head></html>
      """

      assert %{title: "Reversed OG Title"} = MetadataParser.parse(html, @base_url)
    end
  end

  describe "HTML entity decoding" do
    test "decodes &amp; &lt; &gt; &quot; &#39; in title" do
      html = """
      <html><head>
        <meta property="og:title" content="Tom &amp; Jerry &lt;3&gt; &quot;Friends&quot; &#39;Forever&#39;">
      </head></html>
      """

      result = MetadataParser.parse(html, @base_url)
      assert result.title == "Tom & Jerry <3> \"Friends\" 'Forever'"
    end

    test "decodes HTML entities in description" do
      html = """
      <html><head>
        <meta property="og:description" content="A &amp; B">
      </head></html>
      """

      assert %{description: "A & B"} = MetadataParser.parse(html, @base_url)
    end
  end

  describe "edge cases" do
    test "nil HTML returns all-nil map" do
      assert %{title: nil, description: nil, favicon_url: nil} =
               MetadataParser.parse(nil, @base_url)
    end

    test "empty string HTML returns all-nil map" do
      assert %{title: nil, description: nil, favicon_url: nil} =
               MetadataParser.parse("", @base_url)
    end

    test "malformed HTML without head returns all-nil or partial results" do
      html = "<div>just a div, no head</div>"

      result = MetadataParser.parse(html, @base_url)
      assert result.title == nil
      assert result.description == nil
      # favicon falls back to /favicon.ico even without a head
      assert result.favicon_url == "https://example.com/favicon.ico"
    end
  end
end
