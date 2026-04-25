defmodule Liminal.Links.Janitor do
  @moduledoc """
  Periodic GenServer that cleans up expired link_tags and orphaned links.

  Runs an immediate sweep on startup, then repeats every 5 minutes.
  """

  use GenServer

  @sweep_interval_ms :timer.minutes(5)

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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

    if Application.get_env(:liminal, :start_indexer, true) do
      Liminal.Links.list_unindexed_links()
      |> Enum.each(fn link ->
        Task.Supervisor.start_child(
          Liminal.Links.IndexerTaskSupervisor,
          fn -> Liminal.Links.Indexer.index(link.id, link.user_id) end
        )
      end)
    end

    schedule_sweep(@sweep_interval_ms)
    {:noreply, state}
  end

  defp schedule_sweep(delay_ms) do
    Process.send_after(self(), :sweep, delay_ms)
  end
end
