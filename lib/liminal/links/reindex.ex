defmodule Liminal.Links.Reindex do
  @moduledoc """
  Coordinates async link reindexing jobs at link, user, or instance scope.

  A named GenServer holds the active job in memory and serializes starts via
  `call/2`, so only one reindex job runs at a time. Work is drained in
  rate-limited batches to avoid overloading the instance. Progress is broadcast
  on `"links:reindex"` for LiveViews to subscribe to.
  """

  use GenServer

  alias Liminal.Links
  alias Liminal.Links.{ReindexJob, ReindexRunner}

  @pubsub_topic "links:reindex"

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
    {:ok, ReindexJob.idle_state()}
  end

  @impl true
  def handle_call(:active?, _from, state) do
    {:reply, ReindexJob.running?(state), state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, ReindexJob.public_status(state), state}
  end

  @impl true
  def handle_call({:start_job, _scope, _opts}, _from, %{active_job: %{} = _job} = state) do
    {:reply, {:error, :already_running}, state}
  end

  @impl true
  def handle_call({:start_job, scope, opts}, _from, _state) do
    link_ids = Links.list_reindex_link_ids(scope)
    total = length(link_ids)
    requested_by = Keyword.get(opts, :requested_by)

    reply_start_job(scope, total, requested_by, link_ids)
  end

  @impl true
  def handle_call(:cancel, _from, %{active_job: nil} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    state = ReindexRunner.cancel_timer(state)
    cancelled = state.active_job
    new_state = ReindexJob.idle_state() |> ReindexJob.put_last_job(cancelled, :cancelled)
    broadcast_progress(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:process_batch, %{active_job: %{} = _job} = state) do
    {state, done?} = ReindexRunner.process_batch(state)
    {:noreply, after_batch(state, done?)}
  end

  defp reply_start_job(_scope, 0, _requested_by, _link_ids) do
    idle = ReindexJob.idle_state()
    {:reply, {:ok, ReindexJob.public_status(idle)}, idle}
  end

  defp reply_start_job(scope, total, requested_by, link_ids) do
    job = ReindexJob.build(scope, total, requested_by, link_ids)
    state = %{ReindexJob.idle_state() | active_job: job}

    case ReindexJob.start_strategy(total, scope) do
      :immediate ->
        reply_immediate_start(state)

      :scheduled ->
        broadcast_progress(state)
        scheduled = ReindexRunner.schedule_batch(state)
        {:reply, {:ok, ReindexJob.public_status(scheduled)}, scheduled}
    end
  end

  defp reply_immediate_start(state) do
    {state, _} = ReindexRunner.process_batch(state)
    finished_state = ReindexRunner.finish_job(state)
    broadcast_progress(finished_state)
    {:reply, {:ok, ReindexJob.public_status(finished_state)}, finished_state}
  end

  defp after_batch(state, true) do
    finished_state = ReindexRunner.finish_job(state)
    broadcast_progress(finished_state)
    finished_state
  end

  defp after_batch(state, false) do
    broadcast_progress(state)
    ReindexRunner.schedule_batch(%{state | active_job: %{state.active_job | timer_ref: nil}})
    state
  end

  defp broadcast_progress(state) do
    Phoenix.PubSub.broadcast(
      Liminal.PubSub,
      @pubsub_topic,
      {:reindex_progress, ReindexJob.public_status(state)}
    )
  end
end
