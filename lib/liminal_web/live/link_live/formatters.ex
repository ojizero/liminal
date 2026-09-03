defmodule LiminalWeb.LinkLive.Formatters do
  alias Liminal.Links

  def time_remaining(nil), do: nil

  def time_remaining(expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now()) do
      diff when diff <= 0 -> "Expired"
      diff -> "Expires in #{humanize_duration(diff)}"
    end
  end

  @doc """
  Renders a link's expiry for a card badge.

  While the owner's expiries are paused the countdown is reported as held rather
  than ticking, since `expires_at` moves with the pause and would otherwise read as
  a deadline that never arrives.
  """
  def expiry_label(nil, _pause), do: nil

  def expiry_label(expires_at, pause) do
    if Links.expiry_paused?(pause) do
      "Paused · #{time_left(expires_at)} left"
    else
      time_remaining(expires_at)
    end
  end

  @doc "Renders the hover detail behind `expiry_label/2`."
  def expiry_tooltip(nil, _pause), do: nil

  def expiry_tooltip(expires_at, pause) do
    if Links.expiry_paused?(pause) do
      "Expiry paused — #{time_left(expires_at)} left when you resume"
    else
      format_datetime(expires_at)
    end
  end

  @doc """
  Renders how long a single tag has left, taking the owner's pause into account.
  """
  def tag_expiry_label(%{expires_at: nil}, _pause), do: nil

  def tag_expiry_label(%{expires_at: expires_at}, pause) do
    expires_at
    |> Links.expiry_wall_clock(pause)
    |> expiry_label(pause)
  end

  defp time_left(expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now()) do
      diff when diff <= 0 -> "no time"
      diff -> humanize_duration(diff)
    end
  end

  defp humanize_duration(seconds) do
    cond do
      seconds < 3600 -> "#{div(seconds, 60)} min"
      seconds < 86_400 -> "#{div(seconds, 3600)} hours"
      seconds < 86_400 * 30 -> "#{div(seconds, 86_400)} days"
      seconds < 86_400 * 365 -> "#{div(seconds, 86_400 * 30)} months"
      true -> "#{div(seconds, 86_400 * 365)} years"
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
