defmodule Liminal.Links.ReindexJob do
  @moduledoc false

  @type mode :: :all | :failed
  @type job_scope ::
          {:link, Ecto.UUID.t()}
          | {:user, Ecto.UUID.t(), mode()}
          | {:instance, mode()}

  def idle_state do
    %{active_job: nil, last_job: nil}
  end

  def running?(%{active_job: nil}), do: false
  def running?(%{active_job: _}), do: true

  def job_mode({:link, _}), do: :failed
  def job_mode({:user, _, mode}) when mode in [:all, :failed], do: mode
  def job_mode({:instance, mode}) when mode in [:all, :failed], do: mode

  def build(scope, total, requested_by, link_ids) do
    %{
      scope: scope,
      mode: job_mode(scope),
      requested_by: requested_by,
      total: total,
      processed: 0,
      queue: :queue.from_list(link_ids),
      timer_ref: nil,
      started_at: DateTime.utc_now(:second)
    }
  end

  def start_strategy(1, {:link, _}), do: :immediate
  def start_strategy(_total, _scope), do: :scheduled

  def put_last_job(state, job, outcome) do
    %{
      state
      | last_job:
          Map.merge(
            Map.take(job, [:scope, :mode, :total, :processed, :started_at, :requested_by]),
            %{outcome: outcome}
          )
    }
  end

  def public_status(%{active_job: nil, last_job: last_job}) do
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

  def public_status(%{active_job: job, last_job: last_job}) do
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
end
