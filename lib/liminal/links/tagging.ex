defmodule Liminal.Links.Tagging do
  @moduledoc """
  Link/tag association mutations and orphan cleanup.
  """

  import Ecto.Query

  alias Liminal.Links.{Events, ExpiryPause, Link, LinkTag, Query, Tag}
  alias Liminal.Repo

  @doc """
  Merges tags onto an existing link.
  """
  def merge_link_tags(scope, link, tag_ids) when is_list(tag_ids) and tag_ids != [] do
    user_id = scope.user.id
    ^user_id = link.user_id

    with {:ok, tags} <- fetch_owned_tags(user_id, tag_ids) do
      now = DateTime.utc_now(:second)
      expiry_now = ExpiryPause.expiry_now(user_id, now)
      existing_tag_ids = MapSet.new(Enum.map(link.link_tags, & &1.tag_id))

      Repo.transaction(fn ->
        Enum.each(tags, &upsert_link_tag(link, &1, now, expiry_now, existing_tag_ids))
        Query.get_link!(scope, link.id)
      end)
      |> case do
        {:ok, updated_link} ->
          Events.broadcast_link_updated(user_id, updated_link)
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
  Tags a link with a tag. Computes `expires_at` from the tag's `expires_in_days`.
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
          expires_at: expires_at(tag, ExpiryPause.expiry_now(user_id, now)),
          inserted_at: now
        },
        on_conflict: :nothing
      )

    case result do
      {:ok, _link_tag} ->
        updated_link = Repo.preload(link, [link_tags: :tag], force: true)
        Events.broadcast_link_updated(user_id, updated_link)
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
  Removes a link_tag and deletes the owning link if it has no remaining tags.
  """
  def cleanup_link(link_tag_id) when is_binary(link_tag_id) do
    LinkTag
    |> Repo.get(link_tag_id)
    |> cleanup_link_tag()
  end

  @doc """
  Scoped version — looks up the link_tag from the link/tag pair and verifies ownership.
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

  @doc """
  Returns the deadline for a tag applied at `expiry_now`.

  `expiry_now` is an expiry-clock reading, not a wall-clock one — see
  `Liminal.Links.ExpiryPause.expiry_now/2`.
  """
  def expires_at(%Tag{expires_in_days: nil}, _expiry_now), do: nil

  def expires_at(%Tag{expires_in_days: days}, expiry_now) do
    DateTime.add(expiry_now, days, :day)
  end

  defp fetch_owned_tags(user_id, tag_ids) do
    tags =
      from(t in Tag, where: t.id in ^tag_ids and t.user_id == ^user_id)
      |> Repo.all()

    validate_tag_count(tags, tag_ids)
  end

  defp validate_tag_count(tags, tag_ids) when length(tags) == length(tag_ids), do: {:ok, tags}
  defp validate_tag_count(_tags, _tag_ids), do: {:error, :invalid_tags}

  defp upsert_link_tag(link, tag, now, expiry_now, existing_tag_ids) do
    case MapSet.member?(existing_tag_ids, tag.id) do
      true -> refresh_link_tag_expiry(link, tag, expiry_now)
      false -> insert_link_tag(link, tag, now, expiry_now)
    end
  end

  defp refresh_link_tag_expiry(link, tag, expiry_now) do
    from(lt in LinkTag,
      where: lt.link_id == ^link.id and lt.tag_id == ^tag.id
    )
    |> Repo.update_all(set: [expires_at: expires_at(tag, expiry_now)])
  end

  defp insert_link_tag(link, tag, now, expiry_now) do
    Repo.insert!(%LinkTag{
      link_id: link.id,
      tag_id: tag.id,
      expires_at: expires_at(tag, expiry_now),
      inserted_at: now
    })
  end

  defp cleanup_link_tag(nil), do: {:ok, :tag_removed}

  defp cleanup_link_tag(%LinkTag{} = link_tag) do
    link_id = link_tag.link_id
    untag_link(link_tag.id)

    link_id
    |> remaining_tag_count()
    |> finish_cleanup(link_id)
  end

  defp remaining_tag_count(link_id) do
    from(lt in LinkTag, where: lt.link_id == ^link_id)
    |> Repo.aggregate(:count)
  end

  defp finish_cleanup(0, link_id), do: delete_orphaned_link(link_id)
  defp finish_cleanup(_remaining, link_id), do: broadcast_remaining_link(link_id)

  defp delete_orphaned_link(link_id) do
    link = Repo.get(Link, link_id)

    from(l in Link, where: l.id == ^link_id)
    |> Repo.delete_all()

    maybe_broadcast_deleted(link, link_id)
    {:ok, :link_deleted}
  end

  defp maybe_broadcast_deleted(nil, _link_id), do: :ok

  defp maybe_broadcast_deleted(%Link{} = link, link_id) do
    Liminal.Links.ImageDownloader.delete(link.image_path)
    Events.broadcast_link_deleted(link.user_id, link_id)
  end

  defp broadcast_remaining_link(link_id) do
    link = Repo.get!(Link, link_id) |> Repo.preload(link_tags: :tag)
    Events.broadcast_link_updated(link.user_id, link)
    {:ok, :tag_removed}
  end
end
