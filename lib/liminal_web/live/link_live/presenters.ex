defmodule LiminalWeb.LinkLive.Presenters do
  @moduledoc false

  alias Liminal.Links

  def time_remaining(nil), do: nil

  def time_remaining(expires_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(expires_at, now)

    cond do
      diff_seconds <= 0 -> "Expired"
      diff_seconds < 3600 -> "Expires in #{div(diff_seconds, 60)} min"
      diff_seconds < 86_400 -> "Expires in #{div(diff_seconds, 3600)} hours"
      diff_seconds < 86_400 * 30 -> "Expires in #{div(diff_seconds, 86_400)} days"
      diff_seconds < 86_400 * 365 -> "Expires in #{div(diff_seconds, 86_400 * 30)} months"
      true -> "Expires in #{div(diff_seconds, 86_400 * 365)} years"
    end
  end

  def index_status(link) do
    cond do
      not is_nil(link.indexed_at) ->
        :indexed

      not is_nil(link.index_gave_up_at) ->
        :gave_up

      not is_nil(link.index_next_attempt_at) and
          DateTime.compare(link.index_next_attempt_at, DateTime.utc_now(:second)) == :gt ->
        :scheduled

      true ->
        :pending
    end
  end

  def time_until(nil), do: "soon"

  def time_until(at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(at, now)

    cond do
      diff_seconds <= 0 -> "now"
      diff_seconds < 3600 -> "in #{div(diff_seconds, 60)} min"
      diff_seconds < 86_400 -> "in #{div(diff_seconds, 3600)} hours"
      true -> "in #{div(diff_seconds, 86_400)} days"
    end
  end

  def format_datetime(nil), do: "unknown"

  def format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  def format_video_duration(seconds) do
    Links.Duration.format(seconds)
  end

  def link_display_title(link), do: link.title || link.url

  def link_host(link) do
    URI.parse(link.url).host || link.url
  end

  def mark_viewed_label(%{viewed_at: nil} = link) do
    "Mark #{link_display_title(link)} as viewed"
  end

  def mark_viewed_label(link) do
    "Mark #{link_display_title(link)} as unviewed"
  end
end
