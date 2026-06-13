defmodule Liminal.Links.VideoMetadataTest do
  use ExUnit.Case, async: true

  alias Liminal.Links.VideoMetadata

  describe "video_url?/1" do
    test "detects YouTube watch and short URLs" do
      assert VideoMetadata.video_url?("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      assert VideoMetadata.video_url?("https://youtu.be/dQw4w9WgXcQ")
      assert VideoMetadata.video_url?("https://www.youtube.com/shorts/abc123")
    end

    test "detects Vimeo video URLs" do
      assert VideoMetadata.video_url?("https://vimeo.com/7806742")
      assert VideoMetadata.video_url?("https://player.vimeo.com/video/7806742")
    end

    test "rejects non-video URLs" do
      refute VideoMetadata.video_url?("https://example.com/article")
      refute VideoMetadata.video_url?("https://www.youtube.com/")
    end
  end

  describe "fetch_duration/3" do
    test "parses YouTube duration from itemprop metadata" do
      html = ~s(<meta itemprop="duration" content="PT4M13S">)

      assert VideoMetadata.fetch_duration(
               "https://www.youtube.com/watch?v=abc123",
               html
             ) == 253
    end

    test "parses YouTube duration from embedded player JSON" do
      html = ~s(var ytInitialPlayerResponse = {"videoDetails":{"lengthSeconds":"822"}};)

      assert VideoMetadata.fetch_duration(
               "https://www.youtube.com/watch?v=abc123",
               html
             ) == 822
    end

    test "returns nil for non-video URLs" do
      assert VideoMetadata.fetch_duration("https://example.com", "<html></html>") == nil
    end
  end
end
