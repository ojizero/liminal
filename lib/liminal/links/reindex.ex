defmodule Liminal.Links.Reindex do
  @moduledoc """
  Coordinates async link reindexing jobs at link, user, or instance scope.

  A named GenServer holds the active job in memory and serializes starts via
  `call/2`, so only one reindex job runs at a time. Work is drained in
  rate-limited batches to avoid overloading the instance. Progress is broadcast
  on `"links:reindex"` for LiveViews to subscribe to.
  """

  use GenServer

  alias Liminal.Links.{Indexing, Link}
  alias Liminal.Repo

  @pubsub_topic "links:reindex"

  @default_batch_size 3
  @default_interval_ms 2_000

  @type mode :: :all | :failed
  @type job_scope ::
          {:link, Ecto.UUID.t()}
          | {:user, Ecto.UUID.t(), mode()}
          | {:instance, mode()}

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns whether a reindex job is currently running."
  def active? do
    GenServer.call(__MODULE__, :active?)
  end

  @doc "Returns the current reindex job state."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Starts a reindex job for the given scope.

  Returns `{:ok, job}` or `{:error, :already_running}`.

  ## Scopes

    * `{:link, link_id}` — one link
    * `{:user, user_id, mode}` — all or failed links for a user
    * `{:instance, mode}` — all or failed links instance-wide (admin)

  """
  def start_job(scope, opts \\ []) when is_tuple(scope) do
    GenServer.call(__MODULE__, {:start_job, scope, opts})
  end

  @doc "Cancels the in-flight reindex job."
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
  def handle_call(:active?, _from, state) do
    {:reply, running?(state), state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, public_status(state), state}
  end

  @impl true
  def handle_call({:start_job, _scope, _opts}, _from, %{active_job: %{} = _job} = state) do
    {:reply, {:error, :already_running}, state}
  end

  @impl true
  def handle_call({:start_job, scope, opts}, _from, _state) do
    link_ids = Indexing.list_reindex_link_ids(scope)
    requested_by = Keyword.get(opts, :requested_by)

    start_job_reply(scope, requested_by, link_ids)
  end

  @impl true
  def handle_call(:cancel, _from, %{active_job: nil} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    state = cancel_timer(state)
    cancelled = state.active_job
    new_state = idle_state() |> put_last_job(cancelled, :cancelled)
    broadcast_progress(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:process_batch, %{active_job: %{} = _job} = state) do
    state
    |> process_batch()
    |> batch_reply()
  end

  ## Internals

  defp idle_state do
    %{active_job: nil, last_job: nil}
  end

  defp running?(%{active_job: nil}), do: false
  defp running?(%{active_job: _}), do: true

  defp start_job_reply(_scope, _requested_by, []) do
    state = idle_state()
    {:reply, {:ok, public_status(state)}, state}
  end

  defp start_job_reply({:link, _} = scope, requested_by, [_link_id] = link_ids) do
    state = build_job_state(scope, requested_by, link_ids)
    {state, _done?} = process_batch(state)
    finished_state = finish_job(state)
    broadcast_progress(finished_state)
    {:reply, {:ok, public_status(finished_state)}, finished_state}
  end

  defp start_job_reply(scope, requested_by, link_ids) do
    state = build_job_state(scope, requested_by, link_ids)

    broadcast_progress(state)
    schedule_batch(state)
    {:reply, {:ok, public_status(state)}, state}
  end

  defp build_job_state(scope, requested_by, link_ids) do
    job = %{
      scope: scope,
      mode: job_mode(scope),
      requested_by: requested_by,
      total: length(link_ids),
      processed: 0,
      queue: :queue.from_list(link_ids),
      timer_ref: nil,
      started_at: DateTime.utc_now(:second)
    }

    %{idle_state() | active_job: job}
  end

  defp job_mode({:link, _}), do: :failed
  defp job_mode({:user, _, mode}) when mode in [:all, :failed], do: mode
  defp job_mode({:instance, mode}) when mode in [:all, :failed], do: mode

  defp process_batch(%{active_job: job} = state) do
    batch_size = batch_size()
    {link_ids, queue} = dequeue(job.queue, batch_size, [])

    Enum.each(link_ids, fn link_id ->
      case Repo.get(Link, link_id) do
        nil ->
          :ok

        link ->
          Indexing.prepare_link_for_reindex(link, job.mode)
          Indexing.queue_index(link.id, link.user_id)
      end
    end)

    updated_job = %{
      job
      | processed: job.processed + length(link_ids),
        queue: queue
    }

    done? = :queue.is_empty(queue)
    {%{state | active_job: updated_job}, done?}
  end

  defp batch_reply({state, true}) do
    finished_state = finish_job(state)
    broadcast_progress(finished_state)
    {:noreply, finished_state}
  end

  defp batch_reply({state, false}) do
    broadcast_progress(state)
    schedule_batch(%{state | active_job: %{state.active_job | timer_ref: nil}})
    {:noreply, state}
  end

  defp finish_job(%{active_job: job}) do
    idle_state() |> put_last_job(job, :completed)
  end

  defp put_last_job(state, job, outcome) do
    %{
      state
      | last_job:
          Map.merge(
            Map.take(job, [:scope, :mode, :total, :processed, :started_at, :requested_by]),
            %{outcome: outcome}
          )
    }
  end

  defp dequeue(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp dequeue(queue, n, acc) do
    case :queue.out(queue) do
      {{:value, id}, rest} -> dequeue(rest, n - 1, [id | acc])
      {:empty, _} -> {Enum.reverse(acc), queue}
    end
  end

  defp schedule_batch(%{active_job: job} = state) do
    ref = Process.send_after(self(), :process_batch, interval_ms())
    %{state | active_job: %{job | timer_ref: ref}}
  end

  defp cancel_timer(%{active_job: %{timer_ref: ref} = job} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | active_job: %{job | timer_ref: nil}}
  end

  defp cancel_timer(state), do: state

  defp public_status(%{active_job: nil, last_job: last_job}) do
    %{
      active: false,
      status: :idle,
      scope: nil,
      mode: nil,
      total: 0,
      processed: 0,
      remaining: 0,
      started_at: nil,
      requested_by: nil,
      last_job: public_last_job(last_job)
    }
  end

  defp public_status(%{active_job: job, last_job: last_job}) do
    %{
      active: true,
      status: :running,
      scope: job.scope,
      mode: job.mode,
      total: job.total,
      processed: job.processed,
      remaining: :queue.len(job.queue),
      started_at: job.started_at,
      requested_by: job.requested_by,
      last_job: public_last_job(last_job)
    }
  end

  defp public_last_job(nil), do: nil

  defp public_last_job(job) do
    Map.take(job, [:scope, :mode, :total, :processed, :started_at, :requested_by, :outcome])
  end

  defp broadcast_progress(state) do
    Phoenix.PubSub.broadcast(
      Liminal.PubSub,
      @pubsub_topic,
      {:reindex_progress, public_status(state)}
    )
  end

  defp batch_size do
    Application.get_env(:liminal, __MODULE__, [])
    |> Keyword.get(:batch_size, @default_batch_size)
  end

  defp interval_ms do
    Application.get_env(:liminal, __MODULE__, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end
end
