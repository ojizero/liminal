defmodule Liminal.Links.Duration do
  @moduledoc """
  Parses and formats video durations.

  Supports ISO 8601 durations (e.g. `PT4M13S`) and human-readable display
  (e.g. `4:13`, `1:02:03`).
  """

  @iso8601_duration ~r/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$/i

  @doc """
  Parses an ISO 8601 duration string into total seconds.

  Returns `nil` when the value is missing or invalid.
  """
  @spec parse_iso8601(String.t() | nil) :: non_neg_integer() | nil
  def parse_iso8601(nil), do: nil

  def parse_iso8601(value) when is_binary(value) do
    case Regex.run(@iso8601_duration, String.trim(value)) do
      [_, hours, minutes, seconds] ->
        hours = parse_component(hours)
        minutes = parse_component(minutes)
        seconds = parse_component(seconds)

        if hours == 0 and minutes == 0 and seconds == 0 do
          nil
        else
          hours * 3600 + minutes * 60 + seconds
        end

      _ ->
        nil
    end
  end

  @doc """
  Formats a duration in seconds for display on link cards.

  Examples: `45` -> `"0:45"`, `253` -> `"4:13"`, `3723` -> `"1:02:03"`.
  """
  @spec format(non_neg_integer() | nil) :: String.t() | nil
  def format(nil), do: nil

  def format(seconds) when is_integer(seconds) and seconds >= 0 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    if hours > 0 do
      "#{hours}:#{pad(minutes)}:#{pad(secs)}"
    else
      "#{minutes}:#{pad(secs)}"
    end
  end

  defp parse_component(nil), do: 0
  defp parse_component(""), do: 0

  defp parse_component(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> 0
    end
  end

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
