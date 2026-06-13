defmodule Liminal.Links.DurationTest do
  use ExUnit.Case, async: true

  alias Liminal.Links.Duration

  describe "parse_iso8601/1" do
    test "parses minute and second durations" do
      assert Duration.parse_iso8601("PT4M13S") == 253
      assert Duration.parse_iso8601("PT45S") == 45
    end

    test "parses hour durations" do
      assert Duration.parse_iso8601("PT1H2M3S") == 3723
    end

    test "returns nil for invalid values" do
      assert Duration.parse_iso8601(nil) == nil
      assert Duration.parse_iso8601("not-a-duration") == nil
      assert Duration.parse_iso8601("PT0S") == nil
    end
  end

  describe "format/1" do
    test "formats short and long durations" do
      assert Duration.format(45) == "0:45"
      assert Duration.format(253) == "4:13"
      assert Duration.format(3723) == "1:02:03"
    end

    test "returns nil for nil" do
      assert Duration.format(nil) == nil
    end
  end
end
