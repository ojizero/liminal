defmodule Liminal.Links do
  @moduledoc """
  The Links context — manages links, tags, and tagging for users.
  """

  import Ecto.Query

  alias Liminal.Repo
  alias Liminal.Links.{Tag, Link, LinkTag}

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

  """
  def list_links(scope, opts \\ []) do
    filter = Keyword.get(opts, :filter, :unviewed)

    from(l in Link, where: l.user_id == ^scope.user.id, order_by: [desc: l.inserted_at])
    |> apply_link_filter(filter)
    |> Repo.all()
    |> Repo.preload(link_tags: :tag)
  end

  defp apply_link_filter(query, :unviewed) do
    from(l in query, where: is_nil(l.viewed_at))
  end

  defp apply_link_filter(query, :viewed) do
    from(l in query, where: not is_nil(l.viewed_at))
  end

  defp apply_link_filter(query, :all), do: query

  @doc """
  Returns links where indexing hasn't completed yet.
  Uses `indexed_at IS NULL AND inserted_at < now - older_than_minutes` to avoid
  racing with in-progress indexing tasks.
  """
  def list_unindexed_links(opts \\ []) do
    older_than_minutes = Keyword.get(opts, :older_than_minutes, 1)
    limit = Keyword.get(opts, :limit, 10)
    cutoff = DateTime.utc_now(:second) |> DateTime.add(-older_than_minutes, :minute)

    from(l in Link,
      where: is_nil(l.indexed_at) and l.inserted_at < ^cutoff,
      order_by: [asc: l.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Gets a single link by id, scoped to the user, with preloaded tags.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_link!(scope, id) do
    Repo.get_by!(Link, id: id, user_id: scope.user.id)
    |> Repo.preload(link_tags: :tag)
  end

  @doc """
  Updates a link. Verifies ownership via pattern match.
  """
  def update_link(scope, link, attrs) do
    user_id = scope.user.id
    ^user_id = link.user_id

    case link |> Link.changeset(attrs) |> Repo.update() do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        broadcast(user_id, {:link_updated, updated_link})
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
    metadata = Map.put(metadata, :indexed_at, DateTime.utc_now(:second))

    case link |> Link.metadata_changeset(metadata) |> Repo.update() do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        broadcast(link.user_id, {:link_updated, updated_link})
        {:ok, updated_link}

      error ->
        error
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
          user_id =
            from(l in Link, where: l.id == ^link_id, select: l.user_id)
            |> Repo.one()

          from(l in Link, where: l.id == ^link_id) |> Repo.delete_all()

          if user_id, do: broadcast_link_deleted(user_id, link_id)

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

  @doc """
  For each expired link_tag, removes it and deletes the owning link if
  orphaned. Used by the Janitor's periodic sweep.
  """
  def cleanup_expired do
    now = DateTime.utc_now(:second)

    from(lt in LinkTag,
      where: not is_nil(lt.expires_at) and lt.expires_at <= ^now,
      select: lt.id
    )
    |> Repo.all()
    |> Enum.each(&cleanup_link/1)

    :ok
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
          Task.Supervisor.start_child(
            Liminal.Links.IndexerTaskSupervisor,
            fn -> Liminal.Links.Indexer.index(link.id, scope.user.id) end
          )
        end

        {:ok, link}

      {:error, :link, changeset, _changes} ->
        {:error, changeset}

      {:error, :link_tags, reason, _changes} ->
        {:error, reason}
    end
  end
end
