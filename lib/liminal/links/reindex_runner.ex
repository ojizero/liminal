defmodule Liminal.Links.ReindexRunner do
  @moduledoc false

  alias Liminal.Links
  alias Liminal.Links.{Link, ReindexJob}
  alias Liminal.Repo

  @default_batch_size 3
  @default_interval_ms 2_000

  def process_batch(%{active_job: job} = state) do
    batch_size = batch_size()
    {link_ids, queue} = dequeue(job.queue, batch_size, [])

    Enum.each(link_ids, fn link_id ->
      case Repo.get(Link, link_id) do
        nil ->
          :ok

        link ->
          Links.prepare_link_for_reindex(link, job.mode)
          Links.queue_index(link.id, link.user_id)
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

  def finish_job(%{active_job: job}) do
    ReindexJob.idle_state() |> ReindexJob.put_last_job(job, :completed)
  end

  def schedule_batch(%{active_job: job} = state) do
    ref = Process.send_after(self(), :process_batch, interval_ms())
    %{state | active_job: %{job | timer_ref: ref}}
  end

  def cancel_timer(%{active_job: %{timer_ref: ref} = job} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | active_job: %{job | timer_ref: nil}}
  end

  def cancel_timer(state), do: state

  defp dequeue(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp dequeue(queue, n, acc) do
    case :queue.out(queue) do
      {{:value, id}, rest} -> dequeue(rest, n - 1, [id | acc])
      {:empty, _} -> {Enum.reverse(acc), queue}
    end
  end

  defp batch_size do
    Application.get_env(:liminal, Liminal.Links.Reindex, [])
    |> Keyword.get(:batch_size, @default_batch_size)
  end

  defp interval_ms do
    Application.get_env(:liminal, Liminal.Links.Reindex, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end
end
