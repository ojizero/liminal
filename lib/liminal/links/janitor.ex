defmodule Liminal.Links.Janitor do
  @moduledoc """
  Periodic cleanup and index-retry scheduling.

  Orphaned links (no tags left) are deleted here rather than inline so tag
  removal stays fast and expiry batching stays predictable.
  """

  use GenServer

  alias Liminal.Links.{Expiration, Indexing}

  @default_sweep_interval_ms :timer.minutes(5)

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    unless Keyword.get(opts, :skip_initial_sweep, false) do
      schedule_sweep(0)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    Expiration.cleanup_expired()

    if Application.get_env(:liminal, :start_indexer, true) do
      Indexing.list_index_retry_candidates()
      |> Enum.each(&Indexing.queue_index(&1.id, &1.user_id))
    end

    schedule_sweep(sweep_interval_ms())
    {:noreply, state}
  end

  defp schedule_sweep(delay_ms) do
    Process.send_after(self(), :sweep, delay_ms)
  end

  defp sweep_interval_ms do
    Application.get_env(:liminal, :janitor_sweep_interval_ms, @default_sweep_interval_ms)
  end
end
