defmodule Liminal.Links.Mutations do
  @moduledoc """
  Create, update, delete, and changeset helpers for links.
  """

  import Ecto.Query

  alias Liminal.Links.{Events, ExpiryPause, Indexing, Link, LinkTag, Tag, Tagging}
  alias Liminal.Repo

  @doc """
  Creates a link for the given user.
  """
  def create_link(scope, attrs, tag_ids) when is_list(tag_ids) and tag_ids != [] do
    with {:ok, tags} <- fetch_owned_tags(scope, tag_ids) do
      now = DateTime.utc_now(:second)
      create_link_with_tags(scope, attrs, tags, now, ExpiryPause.expiry_now(scope.user.id, now))
    end
  end

  def create_link(_scope, _attrs, []), do: {:error, :no_tags}
  def create_link(_scope, _attrs, _tag_ids), do: {:error, :no_tags}
  def create_link(_scope, _attrs), do: {:error, :no_tags}

  @doc """
  Updates a link. Verifies ownership via pattern match.
  """
  def update_link(scope, link, attrs) do
    user_id = scope.user.id
    ^user_id = link.user_id

    url_changed? = url_changed?(link, attrs)

    link
    |> maybe_delete_image(url_changed?)

    changeset =
      link
      |> Link.changeset(attrs)
      |> maybe_reset_metadata(url_changed?)

    with {:ok, updated_link} <- Repo.update(changeset) do
      updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
      Events.broadcast_link_updated(user_id, updated_link)
      maybe_queue_index(updated_link, user_id, url_changed?)
      {:ok, updated_link}
    end
  end

  @doc """
  Deletes a link. Verifies ownership via pattern match.
  """
  def delete_link(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    with {:ok, _} = result <- Repo.delete(link) do
      Liminal.Links.ImageDownloader.delete(link.image_path)
      Events.broadcast_link_deleted(user_id, link.id)
      result
    end
  end

  @doc "Returns a link changeset for create/edit forms."
  def change_link(link, attrs \\ %{}) do
    Link.changeset(link, attrs)
  end

  defp fetch_owned_tags(scope, tag_ids) do
    tags =
      from(t in Tag,
        where: t.id in ^tag_ids and t.user_id == ^scope.user.id
      )
      |> Repo.all()

    validate_tag_count(tags, tag_ids)
  end

  defp validate_tag_count(tags, tag_ids) when length(tags) == length(tag_ids), do: {:ok, tags}
  defp validate_tag_count(_tags, _tag_ids), do: {:error, :invalid_tags}

  defp create_link_with_tags(scope, attrs, tags, now, expiry_now) do
    link_changeset =
      %Link{}
      |> Link.changeset(attrs)
      |> Ecto.Changeset.put_change(:user_id, scope.user.id)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:link, link_changeset)
    |> Ecto.Multi.run(:link_tags, fn repo, %{link: link} ->
      link_tags = Enum.map(tags, &build_link_tag(link, &1, now, expiry_now))
      inserted = Enum.map(link_tags, &repo.insert!/1)
      {:ok, inserted}
    end)
    |> Repo.transaction()
    |> handle_create_result(scope)
  end

  defp build_link_tag(link, tag, now, expiry_now) do
    %LinkTag{
      link_id: link.id,
      tag_id: tag.id,
      expires_at: Tagging.expires_at(tag, expiry_now),
      inserted_at: now
    }
  end

  defp handle_create_result({:ok, %{link: link}}, scope) do
    link = Repo.preload(link, link_tags: :tag)
    Events.broadcast_link_created(scope.user.id, link)
    Indexing.queue_index(link.id, scope.user.id)
    {:ok, link}
  end

  defp handle_create_result({:error, :link, changeset, _changes}, _scope), do: {:error, changeset}
  defp handle_create_result({:error, :link_tags, reason, _changes}, _scope), do: {:error, reason}

  defp url_changed?(%Link{url: url}, %{"url" => new_url}), do: new_url != url
  defp url_changed?(%Link{}, _attrs), do: false

  defp maybe_delete_image(%Link{} = link, true) do
    Liminal.Links.ImageDownloader.delete(link.image_path)
    link
  end

  defp maybe_delete_image(%Link{} = link, false), do: link

  defp maybe_reset_metadata(changeset, true) do
    changeset
    |> Ecto.Changeset.put_change(:indexed_at, nil)
    |> Ecto.Changeset.put_change(:description, nil)
    |> Ecto.Changeset.put_change(:favicon_url, nil)
    |> Ecto.Changeset.put_change(:image_path, nil)
    |> Ecto.Changeset.put_change(:duration_seconds, nil)
    |> Indexing.put_index_retry_reset_changes()
  end

  defp maybe_reset_metadata(changeset, false), do: changeset

  defp maybe_queue_index(link, user_id, true), do: Indexing.queue_index(link.id, user_id)
  defp maybe_queue_index(_link, _user_id, false), do: nil
end
