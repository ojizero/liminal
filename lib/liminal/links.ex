defmodule Liminal.Links do
  @moduledoc """
  The Links context — manages links, tags, and tagging for users.
  """

  import Ecto.Query

  require Logger

  alias Liminal.Repo
  alias Liminal.Links.{Tag, Link, LinkTag, TextSearch}

  ## PubSub

  @doc "Subscribe the calling process to link events for the given user."
  def subscribe_links(scope) do
    Phoenix.PubSub.subscribe(Liminal.PubSub, topic(scope.user.id))
  end

  defp topic(user_id), do: "user_links:#{user_id}"

  defp broadcast(user_id, message) do
    Phoenix.PubSub.broadcast(Liminal.PubSub, topic(user_id), message)
  end

  defp broadcast_link_deleted(user_id, link_id) do
    broadcast(user_id, {:link_deleted, link_id})
  end

  @default_tags [
    %{name: "saved for later", expires_in_days: 30},
    %{name: "read later", expires_in_days: 14},
    %{name: "watch later", expires_in_days: 30}
  ]

  ## Default tags

  @doc false
  def create_default_tags(user_id) do
    now = DateTime.utc_now(:second)

    Enum.each(@default_tags, fn %{name: name, expires_in_days: expires_in_days} ->
      Repo.insert!(
        %Tag{
          name: name,
          expires_in_days: expires_in_days,
          user_id: user_id,
          inserted_at: now,
          updated_at: now
        },
        on_conflict: :nothing
      )
    end)

    :ok
  end

  ## Tags CRUD

  @doc """
  Lists all tags for the given user, ordered by name.
  """
  def list_tags(scope) do
    from(t in Tag, where: t.user_id == ^scope.user.id, order_by: t.name)
    |> Repo.all()
  end

  @doc """
  Gets a single tag by id, scoped to the user.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_tag!(scope, id) do
    Repo.get_by!(Tag, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a tag for the given user.
  """
  def create_tag(scope, attrs) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, scope.user.id)
    |> Repo.insert()
  end

  @doc """
  Updates a tag. Verifies ownership via pattern match.
  """
  def update_tag(scope, tag, attrs) do
    user_id = scope.user.id
    ^user_id = tag.user_id

    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tag. Verifies ownership via pattern match.
  """
  def delete_tag(scope, tag) do
    user_id = scope.user.id
    ^user_id = tag.user_id

    Repo.delete(tag)
  end

  @doc """
  Returns a changeset for tracking tag changes.
  """
  def change_tag(tag, attrs \\ %{}) do
    Tag.changeset(tag, attrs)
  end

  ## Links CRUD

  @doc """
  Lists links for the given user with preloaded tags.

  ## Options

    * `:filter` - `:unviewed` (default), `:all`, or `:viewed`
    * `:sort` - `:time_added_desc` (default), `:time_added_asc`, or `:expiring_soon`
    * `:tag_ids` - list of tag IDs to filter by (default `[]` = no tag filter)
    * `:query` - fuzzy text search across title, note, description, and URL (default `""`)

  """
  def list_links(scope, opts \\ []) do
    filter = Keyword.get(opts, :filter, :unviewed)
    sort = Keyword.get(opts, :sort, :time_added_desc)
    tag_ids = Keyword.get(opts, :tag_ids, [])
    query = Keyword.get(opts, :query, "")

    from(l in Link, where: l.user_id == ^scope.user.id)
    |> apply_link_filter(filter)
    |> apply_tag_filter(tag_ids)
    |> apply_sort(sort)
    |> Repo.all()
    |> Repo.preload(link_tags: :tag)
    |> TextSearch.filter_links(query)
  end

  @doc """
  Returns a random link for the given user.

  Picks uniformly from all saved links regardless of viewed state or tags.
  """
  def random_link(scope) do
    case from(l in Link,
           where: l.user_id == ^scope.user.id,
           order_by: fragment("RANDOM()"),
           limit: 1
         )
         |> Repo.one() do
      nil -> {:error, :no_links}
      link -> {:ok, Repo.preload(link, link_tags: :tag)}
    end
  end

  defp apply_link_filter(query, :unviewed) do
    from(l in query, where: is_nil(l.viewed_at))
  end

  defp apply_link_filter(query, :viewed) do
    from(l in query, where: not is_nil(l.viewed_at))
  end

  defp apply_link_filter(query, :all), do: query

  defp apply_tag_filter(query, []), do: query

  defp apply_tag_filter(query, tag_ids) do
    from(l in query,
      where:
        l.id in subquery(
          from(lt in LinkTag, where: lt.tag_id in ^tag_ids, select: lt.link_id, distinct: true)
        )
    )
  end

  defp apply_sort(query, :time_added_desc) do
    from(l in query, order_by: [desc: l.inserted_at])
  end

  defp apply_sort(query, :time_added_asc) do
    from(l in query, order_by: [asc: l.inserted_at])
  end

  defp apply_sort(query, :expiring_soon) do
    expiry_sub =
      from(lt in LinkTag,
        group_by: lt.link_id,
        select: %{link_id: lt.link_id, max_expiry: max(lt.expires_at)}
      )

    from(l in query,
      left_join: e in subquery(expiry_sub),
      on: e.link_id == l.id,
      order_by: [asc_nulls_last: e.max_expiry]
    )
  end

  @doc """
  Returns links eligible for indexing retry.

  Uses `indexed_at IS NULL AND inserted_at < now - older_than_minutes` to avoid
  racing with in-progress indexing tasks. Respects backoff via `index_next_attempt_at`
  and excludes links where the Janitor has given up (`index_gave_up_at`).
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

  @doc false
  def list_unindexed_links(opts \\ []), do: list_index_retry_candidates(opts)

  @doc """
  Gets a single link by id, scoped to the user, with preloaded tags.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_link!(scope, id) do
    Repo.get_by!(Link, id: id, user_id: scope.user.id)
    |> Repo.preload(link_tags: :tag)
  end

  @doc """
  Finds a link by URL for the given user, or `nil` if not found.
  """
  def find_link_by_url(scope, url) when is_binary(url) do
    from(l in Link,
      where: l.user_id == ^scope.user.id and l.url == ^url,
      preload: [link_tags: :tag]
    )
    |> Repo.one()
  end

  @doc """
  Updates a link. Verifies ownership via pattern match.

  When the URL changes, clears indexed metadata and re-queues indexing.
  """
  def update_link(scope, link, attrs) do
    user_id = scope.user.id
    ^user_id = link.user_id

    url_changed? = Map.has_key?(attrs, "url") and attrs["url"] != link.url

    if url_changed? and link.image_path do
      Liminal.Links.ImageDownloader.delete(link.image_path)
    end

    changeset = link |> Link.changeset(attrs)

    changeset =
      if url_changed? do
        changeset
        |> Ecto.Changeset.put_change(:indexed_at, nil)
        |> Ecto.Changeset.put_change(:description, nil)
        |> Ecto.Changeset.put_change(:favicon_url, nil)
        |> Ecto.Changeset.put_change(:image_path, nil)
        |> Ecto.Changeset.put_change(:duration_seconds, nil)
        |> put_index_retry_reset_changes()
      else
        changeset
      end

    case Repo.update(changeset) do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        broadcast(user_id, {:link_updated, updated_link})

        if url_changed? do
          spawn_index_task(updated_link.id, user_id)
        end

        {:ok, updated_link}

      error ->
        error
    end
  end

  @doc """
  Deletes a link. Verifies ownership via pattern match.
  """
  def delete_link(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    case Repo.delete(link) do
      {:ok, _} = result ->
        Liminal.Links.ImageDownloader.delete(link.image_path)
        broadcast_link_deleted(user_id, link.id)
        result

      error ->
        error
    end
  end

  @doc """
  Returns a changeset for tracking link changes.
  """
  def change_link(link, attrs \\ %{}) do
    Link.changeset(link, attrs)
  end

  @doc """
  Updates a link's metadata fields from the indexer.
  Only sets title from metadata if the user hasn't already provided one.
  """
  def update_link_metadata(link, metadata) do
    # Only set title from metadata if the user hasn't provided one
    metadata = if link.title, do: Map.delete(metadata, :title), else: metadata

    metadata =
      metadata
      |> Map.put(:indexed_at, DateTime.utc_now(:second))
      |> Map.merge(index_retry_reset_attrs())

    case link |> Link.metadata_changeset(metadata) |> Repo.update() do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        broadcast(link.user_id, {:link_updated, updated_link})
        {:ok, updated_link}

      error ->
        error
    end
  end

  @doc """
  Records a failed indexing attempt and schedules the next retry or gives up.
  """
  def record_index_failure(%Link{} = link) do
    now = DateTime.utc_now(:second)
    attempt_count = link.index_attempt_count + 1

    attrs =
      %{
        index_attempt_count: attempt_count,
        index_last_attempted_at: now
      }
      |> then(fn base ->
        if Liminal.Retry.give_up?(attempt_count) do
          Map.merge(base, %{
            index_gave_up_at: now,
            index_next_attempt_at: nil
          })
        else
          Map.merge(base, %{
            index_next_attempt_at: Liminal.Retry.next_attempt_at(attempt_count, now),
            index_gave_up_at: nil
          })
        end
      end)

    case link |> Link.index_retry_changeset(attrs) |> Repo.update() do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        broadcast(link.user_id, {:link_updated, updated_link})
        {:ok, updated_link}

      error ->
        error
    end
  end

  @doc """
  Resets indexing retry state for a link.
  """
  def reset_index_retry(%Link{} = link) do
    case link |> Link.index_retry_changeset(index_retry_reset_attrs()) |> Repo.update() do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        broadcast(link.user_id, {:link_updated, updated_link})
        {:ok, updated_link}

      error ->
        error
    end
  end

  @doc """
  Resets retry state and re-queues indexing for a link.
  """
  def retry_indexing(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    with {:ok, updated_link} <- reset_index_retry(link) do
      spawn_index_task(updated_link.id, user_id)
      {:ok, updated_link}
    end
  end

  ## Viewed state

  @doc """
  Marks a link as viewed with the current timestamp.
  """
  def mark_viewed(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    case link |> Ecto.Changeset.change(viewed_at: DateTime.utc_now(:second)) |> Repo.update() do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        broadcast(user_id, {:link_updated, updated_link})
        {:ok, updated_link}

      error ->
        error
    end
  end

  @doc """
  Marks a link as unviewed by clearing the viewed_at timestamp.
  """
  def mark_unviewed(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    case link |> Ecto.Changeset.change(viewed_at: nil) |> Repo.update() do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        broadcast(user_id, {:link_updated, updated_link})
        {:ok, updated_link}

      error ->
        error
    end
  end

  ## Tagging

  @doc """
  Merges tags onto an existing link.

  Tags included in `tag_ids` are added if new, or have their expiry refreshed
  if already assigned. Tags on the link that are not in `tag_ids` are unchanged.
  """
  def merge_link_tags(scope, link, tag_ids) when is_list(tag_ids) and tag_ids != [] do
    user_id = scope.user.id
    ^user_id = link.user_id

    tags =
      from(t in Tag, where: t.id in ^tag_ids and t.user_id == ^user_id)
      |> Repo.all()

    if length(tags) != length(tag_ids) do
      {:error, :invalid_tags}
    else
      now = DateTime.utc_now(:second)
      existing_tag_ids = MapSet.new(Enum.map(link.link_tags, & &1.tag_id))

      case Repo.transaction(fn ->
             Enum.each(tags, fn tag ->
               expires_at =
                 if tag.expires_in_days do
                   DateTime.add(now, tag.expires_in_days, :day)
                 end

               if MapSet.member?(existing_tag_ids, tag.id) do
                 from(lt in LinkTag,
                   where: lt.link_id == ^link.id and lt.tag_id == ^tag.id
                 )
                 |> Repo.update_all(set: [expires_at: expires_at])
               else
                 Repo.insert!(%LinkTag{
                   link_id: link.id,
                   tag_id: tag.id,
                   expires_at: expires_at,
                   inserted_at: now
                 })
               end
             end)

             get_link!(scope, link.id)
           end) do
        {:ok, updated_link} ->
          broadcast(user_id, {:link_updated, updated_link})
          {:ok, updated_link}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def merge_link_tags(_scope, _link, _tag_ids) do
    {:error, :no_tags}
  end

  @doc """
  Tags a link with a tag. Computes `expires_at` from the tag's
  `expires_in_days`. Uses `on_conflict: :nothing` for idempotency.
  """
  def tag_link(scope, link, tag) do
    user_id = scope.user.id
    ^user_id = link.user_id
    ^user_id = tag.user_id

    expires_at =
      if tag.expires_in_days do
        DateTime.utc_now(:second) |> DateTime.add(tag.expires_in_days, :day)
      end

    now = DateTime.utc_now(:second)

    result =
      Repo.insert(
        %LinkTag{
          link_id: link.id,
          tag_id: tag.id,
          expires_at: expires_at,
          inserted_at: now
        },
        on_conflict: :nothing
      )

    case result do
      {:ok, _link_tag} ->
        updated_link = Repo.preload(link, [link_tags: :tag], force: true)
        broadcast(user_id, {:link_updated, updated_link})
        result

      error ->
        error
    end
  end

  @doc """
  Removes a link_tag by ID. Idempotent — no-op if already gone.
  """
  def untag_link(link_tag_id) do
    from(lt in LinkTag, where: lt.id == ^link_tag_id)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Removes a link_tag and deletes the owning link if it has no remaining
  tags. Returns `{:ok, :link_deleted}` or `{:ok, :tag_removed}`.
  """
  def cleanup_link(link_tag_id) when is_binary(link_tag_id) do
    case Repo.get(LinkTag, link_tag_id) do
      nil ->
        {:ok, :tag_removed}

      link_tag ->
        link_id = link_tag.link_id
        untag_link(link_tag_id)

        remaining =
          from(lt in LinkTag, where: lt.link_id == ^link_id)
          |> Repo.aggregate(:count)

        if remaining == 0 do
          link = Repo.get(Link, link_id)

          from(l in Link, where: l.id == ^link_id) |> Repo.delete_all()

          if link do
            Liminal.Links.ImageDownloader.delete(link.image_path)
            broadcast_link_deleted(link.user_id, link_id)
          end

          {:ok, :link_deleted}
        else
          link = Repo.get!(Link, link_id) |> Repo.preload(link_tags: :tag)
          broadcast(link.user_id, {:link_updated, link})
          {:ok, :tag_removed}
        end
    end
  end

  @doc """
  Scoped version — looks up the link_tag from the link/tag pair,
  verifies ownership, then delegates to `cleanup_link/1`.
  """
  def cleanup_link(scope, link, tag) do
    user_id = scope.user.id
    ^user_id = link.user_id
    ^user_id = tag.user_id

    case Repo.get_by(LinkTag, link_id: link.id, tag_id: tag.id) do
      nil -> {:ok, :tag_removed}
      lt -> cleanup_link(lt.id)
    end
  end

  ## Expiry cleanup

  @default_viewed_grace_seconds 86_400

  @doc """
  Returns when a link expires.

  For unviewed links, this is the latest tag `expires_at`. For viewed links,
  this is `viewed_at` plus the configured grace period (`:viewed_grace_seconds`,
  default 1 day).
  """
  def link_expires_at(%Link{viewed_at: viewed_at}) when not is_nil(viewed_at) do
    grace_seconds =
      Application.get_env(:liminal, :viewed_grace_seconds, @default_viewed_grace_seconds)

    DateTime.add(viewed_at, grace_seconds, :second)
  end

  def link_expires_at(%Link{} = link) do
    link.link_tags
    |> Enum.map(& &1.expires_at)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      expiries -> Enum.max(expiries, DateTime)
    end
  end

  @doc """
  Deletes links viewed longer than the configured grace period (default 1 day;
  see `:viewed_grace_seconds` application env) with all their tags, then removes
  expired link_tags and deletes orphaned links. Used by the Janitor's periodic sweep.
  """
  def cleanup_expired do
    now = DateTime.utc_now(:second)
    viewed_cutoff = viewed_expiry_cutoff(now)

    stale_viewed_link_ids =
      from(l in Link,
        where: not is_nil(l.viewed_at) and l.viewed_at <= ^viewed_cutoff,
        select: l.id
      )
      |> Repo.all()

    Enum.each(stale_viewed_link_ids, &cleanup_viewed_link/1)

    expired_link_tag_ids =
      from(lt in LinkTag,
        where: not is_nil(lt.expires_at) and lt.expires_at <= ^now,
        select: lt.id
      )
      |> Repo.all()

    Enum.each(expired_link_tag_ids, &cleanup_link/1)

    :ok
  end

  defp viewed_expiry_cutoff(now) do
    grace_seconds =
      Application.get_env(:liminal, :viewed_grace_seconds, @default_viewed_grace_seconds)

    DateTime.add(now, -grace_seconds, :second)
  end

  defp cleanup_viewed_link(link_id) do
    case Repo.get(Link, link_id) do
      nil ->
        :ok

      %Link{} = link ->
        with {:ok, _} <- Repo.transaction(fn -> delete_viewed_link_records(link) end) do
          broadcast_link_deleted(link.user_id, link.id)
          :ok
        else
          {:error, reason} ->
            message =
              "failed to delete viewed link #{link.id} (#{link.url}): #{inspect(reason)}"

            Logger.warning("Links: #{message}")
            {:error, message}
        end
    end
  end

  defp delete_viewed_link_records(link) do
    from(lt in LinkTag, where: lt.link_id == ^link.id) |> Repo.delete_all()
    from(l in Link, where: l.id == ^link.id) |> Repo.delete_all()

    case Liminal.Links.ImageDownloader.delete(link.image_path) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  ## Link creation with tags

  @doc """
  Creates a link for the given user.

  The 3-arity version tags it with the given tag IDs atomically using
  `Ecto.Multi`. The 2-arity version (without tag_ids) always returns
  `{:error, :no_tags}` since links must have at least one tag.
  """
  def create_link(scope, attrs, tag_ids) when is_list(tag_ids) and tag_ids != [] do
    now = DateTime.utc_now(:second)

    tags =
      from(t in Tag,
        where: t.id in ^tag_ids and t.user_id == ^scope.user.id
      )
      |> Repo.all()

    if length(tags) != length(tag_ids) do
      {:error, :invalid_tags}
    else
      create_link_with_tags(scope, attrs, tags, now)
    end
  end

  def create_link(_scope, _attrs, _tag_ids) do
    {:error, :no_tags}
  end

  def create_link(_scope, _attrs) do
    {:error, :no_tags}
  end

  defp create_link_with_tags(scope, attrs, tags, now) do
    link_changeset =
      %Link{}
      |> Link.changeset(attrs)
      |> Ecto.Changeset.put_change(:user_id, scope.user.id)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:link, link_changeset)
    |> Ecto.Multi.run(:link_tags, fn repo, %{link: link} ->
      link_tags =
        Enum.map(tags, fn tag ->
          expires_at =
            if tag.expires_in_days do
              DateTime.add(now, tag.expires_in_days, :day)
            end

          %LinkTag{
            link_id: link.id,
            tag_id: tag.id,
            expires_at: expires_at,
            inserted_at: now
          }
        end)

      inserted = Enum.map(link_tags, &repo.insert!/1)
      {:ok, inserted}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{link: link}} ->
        link = Repo.preload(link, link_tags: :tag)
        broadcast(scope.user.id, {:link_created, link})

        if Application.get_env(:liminal, :start_indexer, true) do
          spawn_index_task(link.id, scope.user.id)
        end

        {:ok, link}

      {:error, :link, changeset, _changes} ->
        {:error, changeset}

      {:error, :link_tags, reason, _changes} ->
        {:error, reason}
    end
  end

  defp spawn_index_task(link_id, user_id) do
    if Application.get_env(:liminal, :start_indexer, true) do
      Task.Supervisor.start_child(
        Liminal.Links.IndexerTaskSupervisor,
        fn -> Liminal.Links.Indexer.index(link_id, user_id) end
      )
    end
  end

  defp index_retry_reset_attrs do
    %{
      index_attempt_count: 0,
      index_last_attempted_at: nil,
      index_next_attempt_at: nil,
      index_gave_up_at: nil
    }
  end

  defp put_index_retry_reset_changes(changeset) do
    Enum.reduce(index_retry_reset_attrs(), changeset, fn {field, value}, cs ->
      Ecto.Changeset.put_change(cs, field, value)
    end)
  end
end
