defmodule LiminalWeb.ExpiryPauseComponents do
  @moduledoc """
  The paused-expiries banner and the settings panel that controls it.

  Both read the pause window straight off the current scope's user, and the
  `resume_expiries` and `pause_expiries` events they push are answered for every
  authenticated LiveView by `LiminalWeb.UserAuth`.
  """

  use LiminalWeb, :html

  alias Liminal.Links

  @doc """
  Ribbon shown under the navbar while a user's expiries are held.

  Renders nothing when there is no pause, so it can sit in the layout unconditionally.
  """
  attr :current_scope, :map, default: nil

  def expiry_pause_banner(assigns) do
    assigns = assign(assigns, :resumes_at, pause_resumes_at(assigns.current_scope))

    ~H"""
    <div
      :if={@resumes_at}
      id="expiry-pause-banner"
      role="status"
      class="border-b border-warning/30 bg-warning/10 px-4 py-2 sm:px-6 lg:px-8"
    >
      <div class="mx-auto flex max-w-6xl flex-wrap items-center gap-x-3 gap-y-1.5 text-sm">
        <span class="flex items-center gap-2 font-medium text-warning">
          <.icon name="hero-pause-circle" class="size-5 shrink-0" /> Expiries paused
        </span>
        <span class="text-base-content/70">
          Nothing expires until {format_pause_date(@resumes_at)}
          <span class="text-base-content/45">({time_until(@resumes_at)})</span>
        </span>
        <button
          id="banner-resume-expiries"
          type="button"
          phx-click="resume_expiries"
          phx-disable-with="Resuming…"
          class="btn btn-xs btn-warning btn-soft ml-auto transition-transform hover:scale-105"
        >
          <.icon name="hero-play" class="size-3.5" /> Resume now
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Settings panel for turning the pause on and choosing how long it runs.
  """
  attr :current_scope, :map, required: true
  attr :pause_form, Phoenix.HTML.Form, required: true

  def expiry_pause_panel(assigns) do
    assigns =
      assigns
      |> assign(:resumes_at, pause_resumes_at(assigns.current_scope))
      |> assign(:duration_options, duration_options())

    ~H"""
    <.panel id="expiry-pause-settings" class="space-y-4">
      <.header level={2}>
        Pause expiries
        <:subtitle>
          Hold every countdown where it is. Nothing expires while paused, and each link
          picks up with the time it had left when you resume.
        </:subtitle>
      </.header>

      <.form for={@pause_form} id="expiry-pause-form" phx-change="pause_expiries" class="max-w-2xl">
        <.input
          field={@pause_form[:enabled]}
          type="checkbox"
          label="Pause expiry counting"
          class="toggle toggle-warning"
        />
        <p class="-mt-1 text-sm text-base-content/60">
          Useful while you are away. Pauses run for up to {Links.max_expiry_pause_days()} days
          and end on their own.
        </p>

        <div class="mt-3 space-y-3">
          <div class="max-w-sm">
            <.input
              field={@pause_form[:days]}
              type="select"
              label="Pause length"
              options={@duration_options}
            />
          </div>

          <div
            :if={@resumes_at}
            id="expiry-pause-status"
            class="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2.5 text-sm"
          >
            <span class="flex items-center gap-2 text-warning">
              <.icon name="hero-pause-circle" class="size-4 shrink-0" />
              Resuming {format_pause_date(@resumes_at)}
            </span>
            <span class="text-base-content/45">{time_until(@resumes_at)}</span>
            <button
              id="settings-resume-expiries"
              type="button"
              phx-click="resume_expiries"
              phx-disable-with="Resuming…"
              class="btn btn-xs btn-warning btn-soft ml-auto transition-transform hover:scale-105"
            >
              <.icon name="hero-play" class="size-3.5" /> Resume now
            </button>
          </div>
        </div>
      </.form>
    </.panel>
    """
  end

  @doc """
  Builds the panel's form from the user's current pause window.

  `days` falls back to `fallback_days` when there is no pause to read a length from,
  which keeps a length the user just picked from snapping back to the default.
  """
  def pause_form(user, fallback_days \\ nil) do
    days =
      case Links.expiry_pause_state(user) do
        nil -> fallback_days || Links.default_expiry_pause_days()
        %{paused_at: paused_at, paused_until: paused_until} -> pause_days(paused_at, paused_until)
      end

    to_form(
      %{"enabled" => Links.expiry_paused?(user), "days" => to_string(days)},
      as: :expiry_pause
    )
  end

  @doc """
  Reads a pause length from form params, falling back to the default when it is
  missing or not one of the offered lengths.
  """
  def parse_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {days, ""} -> parse_days(days)
      _ -> Links.default_expiry_pause_days()
    end
  end

  def parse_days(days) when is_integer(days) do
    if days in Enum.map(Links.expiry_pause_duration_options(), &elem(&1, 1)) do
      days
    else
      Links.default_expiry_pause_days()
    end
  end

  def parse_days(_days), do: Links.default_expiry_pause_days()

  defp duration_options do
    Enum.map(Links.expiry_pause_duration_options(), fn {label, days} ->
      {label, to_string(days)}
    end)
  end

  defp pause_days(paused_at, paused_until) do
    paused_until |> DateTime.diff(paused_at) |> div(86_400) |> max(1)
  end

  defp pause_resumes_at(nil), do: nil

  defp pause_resumes_at(scope) do
    if Links.expiry_paused?(scope), do: Links.expiry_pause_resumes_at(scope)
  end

  defp format_pause_date(at), do: Calendar.strftime(at, "%b %-d at %H:%M UTC")

  defp time_until(at) do
    case DateTime.diff(at, DateTime.utc_now()) do
      diff when diff < 3600 -> "in #{div(diff, 60)} min"
      diff when diff < 86_400 -> "in #{div(diff, 3600)} hours"
      diff -> "in #{div(diff, 86_400)} days"
    end
  end
end
