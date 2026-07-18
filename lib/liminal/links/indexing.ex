defmodule Liminal.Links.Indexing do
  @moduledoc """
  Metadata indexing, retry state, and reindex queue helpers.
  """

  import Ecto.Query

  alias Liminal.Links.{Events, ImageDownloader, Link, Reindex}
  alias Liminal.Repo

  @doc """
  Returns links eligible for indexing retry.
  """
  def list_index_retry_candidates(opts \\ []) do
    older_than_minutes =
      Keyword.get(
        opts,
        :older_than_minutes,
        Application.get_env(:liminal, :index_retry_older_than_minutes, 1)
      )

    limit = Keyword.get(opts, :limit, 10)
    now = DateTime.utc_now(:second)
    cutoff = DateTime.add(now, -older_than_minutes, :minute)

    from(l in Link,
      where: is_nil(l.indexed_at),
      where: is_nil(l.index_gave_up_at),
      where: is_nil(l.index_next_attempt_at) or l.index_next_attempt_at <= ^now,
      where: l.index_attempt_count > 0 or l.inserted_at < ^cutoff,
      order_by: [asc: l.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Legacy alias for `list_index_retry_candidates/1`."
  def list_unindexed_links(opts \\ []), do: list_index_retry_candidates(opts)

  @doc """
  Updates a link's metadata fields from the indexer.
  """
  def update_link_metadata(%Link{} = link, metadata) do
    metadata =
      link
      |> index_metadata(metadata)
      |> Map.put(:indexed_at, DateTime.utc_now(:second))
      |> Map.merge(index_retry_reset_attrs())

    link
    |> Link.metadata_changeset(metadata)
    |> Repo.update()
    |> broadcast_updated_result(link.user_id)
  end

  @doc """
  Records a failed indexing attempt and schedules the next retry or gives up.
  """
  def record_index_failure(%Link{} = link) do
    now = DateTime.utc_now(:second)
    attempt_count = link.index_attempt_count + 1

    attrs =
      %{index_attempt_count: attempt_count, index_last_attempted_at: now}
      |> Map.merge(retry_state_attrs(attempt_count, now))

    link
    |> Link.index_retry_changeset(attrs)
    |> Repo.update()
    |> broadcast_updated_result(link.user_id)
  end

  @doc "Resets indexing retry fields for a link."
  def reset_index_retry(%Link{} = link) do
    link
    |> Link.index_retry_changeset(index_retry_reset_attrs())
    |> Repo.update()
    |> broadcast_updated_result(link.user_id)
  end

  @doc """
  Resets retry state and re-queues indexing for a link via the reindex coordinator.
  """
  def retry_indexing(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    case Reindex.start_job({:link, link.id}, requested_by: user_id) do
      {:ok, _} -> {:ok, Liminal.Links.Query.get_link!(scope, link.id)}
      {:error, :already_running} -> {:error, :reindex_busy}
    end
  end

  @doc """
  Returns link IDs for a reindex job scope.
  """
  def list_reindex_link_ids({:link, link_id}) do
    [link_id]
  end

  def list_reindex_link_ids({:user, user_id, :failed}) do
    reindex_failed_link_ids_query()
    |> where([l], l.user_id == ^user_id)
    |> Repo.all()
  end

  def list_reindex_link_ids({:user, user_id, :all}) do
    from(l in Link, where: l.user_id == ^user_id, select: l.id, order_by: [asc: l.inserted_at])
    |> Repo.all()
  end

  def list_reindex_link_ids({:instance, :failed}) do
    reindex_failed_link_ids_query() |> Repo.all()
  end

  def list_reindex_link_ids({:instance, :all}) do
    from(l in Link, select: l.id, order_by: [asc: l.inserted_at])
    |> Repo.all()
  end

  @doc """
  Resets a link so it can be reindexed.
  """
  def prepare_link_for_reindex(%Link{} = link, :all) do
    delete_image(link)

    attrs =
      %{
        indexed_at: nil,
        description: nil,
        favicon_url: nil,
        image_path: nil,
        duration_seconds: nil
      }
      |> Map.merge(index_retry_reset_attrs())

    link
    |> Link.metadata_changeset(attrs)
    |> Repo.update()
  end

  def prepare_link_for_reindex(%Link{} = link, :failed) do
    reset_index_retry(link)
  end

  @doc "Queues a single link for metadata indexing."
  def queue_index(link_id, user_id) do
    spawn_index_task(link_id, user_id)
  end

  @doc false
  def spawn_index_task(link_id, user_id) do
    if Application.get_env(:liminal, :start_indexer, true) do
      Task.Supervisor.start_child(
        Liminal.Links.IndexerTaskSupervisor,
        fn -> Liminal.Links.Indexer.index(link_id, user_id) end
      )
    end
  end

  @doc false
  def index_retry_reset_attrs do
    %{
      index_attempt_count: 0,
      index_last_attempted_at: nil,
      index_next_attempt_at: nil,
      index_gave_up_at: nil
    }
  end

  @doc false
  def put_index_retry_reset_changes(changeset) do
    Enum.reduce(index_retry_reset_attrs(), changeset, fn {field, value}, cs ->
      Ecto.Changeset.put_change(cs, field, value)
    end)
  end

  defp index_metadata(%Link{title: title}, metadata) when not is_nil(title) do
    Map.delete(metadata, :title)
  end

  defp index_metadata(%Link{}, metadata), do: metadata

  defp retry_state_attrs(attempt_count, now) do
    case Liminal.Retry.give_up?(attempt_count) do
      true ->
        %{index_gave_up_at: now, index_next_attempt_at: nil}

      false ->
        %{
          index_next_attempt_at: Liminal.Retry.next_attempt_at(attempt_count, now),
          index_gave_up_at: nil
        }
    end
  end

  defp reindex_failed_link_ids_query do
    from(l in Link,
      where:
        is_nil(l.indexed_at) and
          (not is_nil(l.index_gave_up_at) or l.index_attempt_count > 0),
      select: l.id,
      order_by: [asc: l.inserted_at]
    )
  end

  defp delete_image(%Link{image_path: image_path}) do
    ImageDownloader.delete(image_path)
  end

  defp broadcast_updated_result({:ok, updated_link}, user_id) do
    updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
    Events.broadcast_link_updated(user_id, updated_link)
    {:ok, updated_link}
  end

  defp broadcast_updated_result(error, _user_id), do: error
end
