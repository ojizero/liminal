defmodule Liminal.Links.LinkTags do
  @moduledoc """
  Link/tag association commands and expiry helpers.
  """

  import Ecto.Query

  alias Liminal.Links.{Link, LinkTag, PubSub, Query, Tag}
  alias Liminal.Repo

  @doc """
  Merges tags onto an existing link.

  Tags included in `tag_ids` are added if new, or have their expiry refreshed
  if already assigned. Tags on the link that are not in `tag_ids` are unchanged.
  """
  def merge_link_tags(scope, link, tag_ids) when is_list(tag_ids) and tag_ids != [] do
    user_id = scope.user.id
    ^user_id = link.user_id

    with {:ok, tags} <- load_and_validate_tags(scope, tag_ids) do
      merge_loaded_tags(scope, link, tags)
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

    now = DateTime.utc_now(:second)

    result =
      Repo.insert(
        %LinkTag{
          link_id: link.id,
          tag_id: tag.id,
          expires_at: tag_expires_at(tag, now),
          inserted_at: now
        },
        on_conflict: :nothing
      )

    case result do
      {:ok, _link_tag} ->
        updated_link = Repo.preload(link, [link_tags: :tag], force: true)
        PubSub.broadcast(user_id, {:link_updated, updated_link})
        result

      error ->
        error
    end
  end

  @doc "Removes a link_tag by ID. Idempotent - no-op if already gone."
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
    LinkTag
    |> Repo.get(link_tag_id)
    |> cleanup_link_tag()
  end

  @doc """
  Scoped version - looks up the link_tag from the link/tag pair,
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

  def load_and_validate_tags(scope, tag_ids) do
    tags =
      from(t in Tag,
        where: t.id in ^tag_ids and t.user_id == ^scope.user.id
      )
      |> Repo.all()

    validate_loaded_tags(tags, tag_ids)
  end

  def tag_expires_at(%Tag{expires_in_days: nil}, _now), do: nil

  def tag_expires_at(%Tag{expires_in_days: days}, now) do
    DateTime.add(now, days, :day)
  end

  def build_link_tags(link, tags, now) do
    Enum.map(tags, fn tag ->
      %LinkTag{
        link_id: link.id,
        tag_id: tag.id,
        expires_at: tag_expires_at(tag, now),
        inserted_at: now
      }
    end)
  end

  defp validate_loaded_tags(tags, tag_ids) when length(tags) == length(tag_ids), do: {:ok, tags}
  defp validate_loaded_tags(_tags, _tag_ids), do: {:error, :invalid_tags}

  defp merge_loaded_tags(scope, link, tags) do
    now = DateTime.utc_now(:second)
    existing_tag_ids = MapSet.new(Enum.map(link.link_tags, & &1.tag_id))

    case Repo.transaction(fn ->
           Enum.each(tags, &upsert_link_tag(link, &1, existing_tag_ids, now))
           Query.get_link!(scope, link.id)
         end) do
      {:ok, updated_link} ->
        PubSub.broadcast(scope.user.id, {:link_updated, updated_link})
        {:ok, updated_link}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_link_tag(link, tag, existing_tag_ids, now) do
    existing_tag_ids
    |> MapSet.member?(tag.id)
    |> upsert_link_tag(link, tag, tag_expires_at(tag, now), now)
  end

  defp upsert_link_tag(true, link, tag, expires_at, _now) do
    from(lt in LinkTag,
      where: lt.link_id == ^link.id and lt.tag_id == ^tag.id
    )
    |> Repo.update_all(set: [expires_at: expires_at])
  end

  defp upsert_link_tag(false, link, tag, expires_at, now) do
    Repo.insert!(%LinkTag{
      link_id: link.id,
      tag_id: tag.id,
      expires_at: expires_at,
      inserted_at: now
    })
  end

  defp cleanup_link_tag(nil), do: {:ok, :tag_removed}

  defp cleanup_link_tag(%LinkTag{} = link_tag) do
    link_id = link_tag.link_id
    untag_link(link_tag.id)

    link_id
    |> remaining_tag_count()
    |> cleanup_after_tag_removed(link_id)
  end

  defp remaining_tag_count(link_id) do
    from(lt in LinkTag, where: lt.link_id == ^link_id)
    |> Repo.aggregate(:count)
  end

  defp cleanup_after_tag_removed(0, link_id) do
    Link
    |> Repo.get(link_id)
    |> cleanup_orphaned_link(link_id)
  end

  defp cleanup_after_tag_removed(_remaining, link_id) do
    link = Repo.get!(Link, link_id) |> Repo.preload(link_tags: :tag)
    PubSub.broadcast(link.user_id, {:link_updated, link})
    {:ok, :tag_removed}
  end

  defp cleanup_orphaned_link(nil, link_id) do
    delete_link_record(link_id)
    {:ok, :link_deleted}
  end

  defp cleanup_orphaned_link(%Link{} = link, link_id) do
    delete_link_record(link_id)
    Liminal.Links.ImageDownloader.delete(link.image_path)
    PubSub.broadcast_link_deleted(link.user_id, link_id)
    {:ok, :link_deleted}
  end

  defp delete_link_record(link_id) do
    from(l in Link, where: l.id == ^link_id) |> Repo.delete_all()
  end
end
