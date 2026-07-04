defmodule Liminal.Links.MassReindexer do
  @moduledoc """
  Rate-limited async mass reindexing for admin operations.

  Queues link IDs and processes them in small batches so indexing does not
  overwhelm the instance. Broadcasts progress on `"admin:reindex"`.
  """

  use GenServer

  alias Liminal.Links
  alias Liminal.Links.Link
  alias Liminal.Repo

  @pubsub_topic "admin:reindex"

  @default_batch_size 3
  @default_interval_ms 2_000

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the current reindex job state."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Starts a mass reindex job.

  `mode` must be `:all` (every link) or `:failed` (only failed indexing attempts).
  Returns `{:ok, job}` or `{:error, :already_running}`.
  """
  def start_reindex(mode) when mode in [:all, :failed] do
    GenServer.call(__MODULE__, {:start_reindex, mode})
  end

  @doc "Cancels the in-flight mass reindex job."
  def cancel do
    GenServer.call(__MODULE__, :cancel)
  end

  @doc false
  def pubsub_topic, do: @pubsub_topic

  ## Server callbacks

  @impl true
  def init(_opts) do
    {:ok, idle_state()}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, public_status(state), state}
  end

  @impl true
  def handle_call({:start_reindex, _mode}, _from, %{status: :running} = state) do
    {:reply, {:error, :already_running}, state}
  end

  @impl true
  def handle_call({:start_reindex, mode}, _from, _state) do
    link_ids = Links.list_mass_reindex_ids(mode)
    total = length(link_ids)
    queue = :queue.from_list(link_ids)

    new_state = %{
      status: if(total == 0, do: :idle, else: :running),
      mode: mode,
      total: total,
      processed: 0,
      queue: queue,
      timer_ref: nil,
      started_at: DateTime.utc_now(:second)
    }

    if total > 0 do
      broadcast_progress(new_state)
      schedule_batch(new_state)
    end

    {:reply, {:ok, public_status(new_state)}, new_state}
  end

  @impl true
  def handle_call(:cancel, _from, %{status: :running} = state) do
    state = cancel_timer(state)
    new_state = idle_state()

    broadcast_progress(%{
      new_state
      | last_job: Map.take(state, [:mode, :total, :processed, :started_at])
    })

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:process_batch, %{status: :running} = state) do
    {state, done?} = process_batch(state)

    cond do
      done? ->
        broadcast_progress(%{state | status: :idle})

        {:noreply,
         %{idle_state() | last_job: Map.take(state, [:mode, :total, :processed, :started_at])}}

      true ->
        broadcast_progress(state)
        schedule_batch(%{state | timer_ref: nil})
        {:noreply, state}
    end
  end

  ## Internals

  defp idle_state do
    %{
      status: :idle,
      mode: nil,
      total: 0,
      processed: 0,
      queue: :queue.new(),
      timer_ref: nil,
      started_at: nil,
      last_job: nil
    }
  end

  defp process_batch(%{queue: queue, mode: mode} = state) do
    batch_size = batch_size()

    {link_ids, queue} = dequeue(queue, batch_size, [])

    Enum.each(link_ids, fn link_id ->
      case Repo.get(Link, link_id) do
        nil ->
          :ok

        link ->
          Links.prepare_link_for_mass_reindex(link, mode)
          Links.queue_index(link.id, link.user_id)
      end
    end)

    processed = state.processed + length(link_ids)
    state = %{state | processed: processed, queue: queue}
    done? = :queue.is_empty(queue)
    {state, done?}
  end

  defp dequeue(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp dequeue(queue, n, acc) do
    case :queue.out(queue) do
      {{:value, id}, rest} -> dequeue(rest, n - 1, [id | acc])
      {:empty, _} -> {Enum.reverse(acc), queue}
    end
  end

  defp schedule_batch(state) do
    ref = Process.send_after(self(), :process_batch, interval_ms())
    %{state | timer_ref: ref}
  end

  defp cancel_timer(%{timer_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  defp cancel_timer(state), do: state

  defp public_status(state) do
    %{
      status: state.status,
      mode: state.mode,
      total: state.total,
      processed: state.processed,
      remaining: :queue.len(state.queue),
      started_at: state.started_at,
      last_job: Map.get(state, :last_job)
    }
  end

  defp broadcast_progress(state) do
    Phoenix.PubSub.broadcast(
      Liminal.PubSub,
      @pubsub_topic,
      {:reindex_progress, public_status(state)}
    )
  end

  defp batch_size do
    Application.get_env(:liminal, Liminal.Links.MassReindexer, [])
    |> Keyword.get(:batch_size, @default_batch_size)
  end

  defp interval_ms do
    Application.get_env(:liminal, Liminal.Links.MassReindexer, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end
end
