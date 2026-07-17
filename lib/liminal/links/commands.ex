defmodule Liminal.Links.Commands do
  @moduledoc """
  Link create, update, delete, and changeset commands.
  """

  alias Liminal.Links.{Indexing, Link, LinkTags, PubSub}
  alias Liminal.Repo

  @doc """
  Creates a link for the given user.

  The 3-arity version tags it with the given tag IDs atomically using
  `Ecto.Multi`. The 2-arity version (without tag_ids) always returns
  `{:error, :no_tags}` since links must have at least one tag.
  """
  def create_link(scope, attrs, tag_ids) when is_list(tag_ids) and tag_ids != [] do
    now = DateTime.utc_now(:second)

    with {:ok, tags} <- LinkTags.load_and_validate_tags(scope, tag_ids) do
      create_link_with_tags(scope, attrs, tags, now)
    end
  end

  def create_link(_scope, _attrs, _tag_ids) do
    {:error, :no_tags}
  end

  def create_link(_scope, _attrs) do
    {:error, :no_tags}
  end

  def create_link_with_tags(scope, attrs, tags, now) do
    link_changeset =
      %Link{}
      |> Link.changeset(attrs)
      |> Ecto.Changeset.put_change(:user_id, scope.user.id)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:link, link_changeset)
    |> Ecto.Multi.run(:link_tags, fn repo, %{link: link} ->
      inserted =
        link
        |> LinkTags.build_link_tags(tags, now)
        |> Enum.map(&repo.insert!/1)

      {:ok, inserted}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{link: link}} ->
        link = Repo.preload(link, link_tags: :tag)
        PubSub.broadcast(scope.user.id, {:link_created, link})
        Indexing.spawn_index_task(link.id, scope.user.id)
        {:ok, link}

      {:error, :link, changeset, _changes} ->
        {:error, changeset}

      {:error, :link_tags, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a link. Verifies ownership via pattern match.

  When the URL changes, clears indexed metadata and re-queues indexing.
  """
  def update_link(scope, link, attrs) do
    user_id = scope.user.id
    ^user_id = link.user_id

    url_changed? = url_changed?(link, attrs)
    maybe_delete_image_on_url_change(url_changed?, link)

    changeset =
      link
      |> Link.changeset(attrs)
      |> apply_url_change_resets(link, url_changed?)

    case Repo.update(changeset) do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        PubSub.broadcast(user_id, {:link_updated, updated_link})
        maybe_reindex(updated_link, user_id, url_changed?)
        {:ok, updated_link}

      error ->
        error
    end
  end

  @doc "Deletes a link. Verifies ownership via pattern match."
  def delete_link(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    case Repo.delete(link) do
      {:ok, _} = result ->
        Liminal.Links.ImageDownloader.delete(link.image_path)
        PubSub.broadcast_link_deleted(user_id, link.id)
        result

      error ->
        error
    end
  end

  @doc "Returns a link changeset for create/edit forms."
  def change_link(link, attrs \\ %{}) do
    Link.changeset(link, attrs)
  end

  defp url_changed?(%Link{url: url}, %{"url" => new_url}), do: new_url != url
  defp url_changed?(%Link{}, _attrs), do: false

  defp maybe_delete_image_on_url_change(true, %Link{image_path: image_path})
       when not is_nil(image_path) do
    Liminal.Links.ImageDownloader.delete(image_path)
  end

  defp maybe_delete_image_on_url_change(_url_changed?, %Link{}), do: :ok

  defp apply_url_change_resets(changeset, %Link{}, true) do
    changeset
    |> Ecto.Changeset.put_change(:indexed_at, nil)
    |> Ecto.Changeset.put_change(:description, nil)
    |> Ecto.Changeset.put_change(:favicon_url, nil)
    |> Ecto.Changeset.put_change(:image_path, nil)
    |> Ecto.Changeset.put_change(:duration_seconds, nil)
    |> Indexing.put_index_retry_reset_changes()
  end

  defp apply_url_change_resets(changeset, %Link{}, false), do: changeset

  defp maybe_reindex(%Link{} = link, user_id, true) do
    Indexing.spawn_index_task(link.id, user_id)
  end

  defp maybe_reindex(%Link{}, _user_id, false), do: :ok
end
