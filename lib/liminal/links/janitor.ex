defmodule Liminal.Links.Janitor do
  @moduledoc """
  Periodic GenServer that cleans up expired link_categories and orphaned links.

  Runs an immediate sweep on startup, then repeats every 5 minutes. Also accepts
  `schedule_cleanup/1` to schedule removal of a specific link_category at its
  expiry time.
  """

  use GenServer

  alias Liminal.Links.LinkCategory

  @sweep_interval_ms :timer.minutes(5)

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Schedules removal of a link_category at its `expires_at` time.

  No-op if the link_category has no expiry.
  """
  def schedule_cleanup(%LinkCategory{expires_at: nil}), do: :ok

  def schedule_cleanup(%LinkCategory{} = link_category) do
    GenServer.cast(__MODULE__, {:schedule_cleanup, link_category.id, link_category.expires_at})
    :ok
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    schedule_sweep(0)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    Liminal.Links.cleanup_expired()
    schedule_sweep(@sweep_interval_ms)
    {:noreply, state}
  end

  def handle_info({:untag, link_category_id}, state) do
    Liminal.Links.untag_link(link_category_id)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:schedule_cleanup, link_category_id, expires_at}, state) do
    delay_ms = max(DateTime.diff(expires_at, DateTime.utc_now(:second), :millisecond), 0)
    Process.send_after(self(), {:untag, link_category_id}, delay_ms)
    {:noreply, state}
  end

  defp schedule_sweep(delay_ms) do
    Process.send_after(self(), :sweep, delay_ms)
  end
end
