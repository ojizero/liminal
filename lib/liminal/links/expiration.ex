defmodule Liminal.Links.Expiration do
  @moduledoc """
  Expiration calculations and janitor cleanup for expired links.
  """

  import Ecto.Query

  require Logger

  alias Liminal.Links.{Link, LinkTag, PubSub}
  alias Liminal.Repo

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

    Enum.each(expired_link_tag_ids, &Liminal.Links.LinkTags.cleanup_link/1)

    :ok
  end

  def viewed_expiry_cutoff(now) do
    grace_seconds =
      Application.get_env(:liminal, :viewed_grace_seconds, @default_viewed_grace_seconds)

    DateTime.add(now, -grace_seconds, :second)
  end

  def cleanup_viewed_link(link_id) do
    case Repo.get(Link, link_id) do
      nil ->
        :ok

      %Link{} = link ->
        with {:ok, _} <- Repo.transaction(fn -> delete_viewed_link_records(link) end) do
          PubSub.broadcast_link_deleted(link.user_id, link.id)
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

  def delete_viewed_link_records(link) do
    from(lt in LinkTag, where: lt.link_id == ^link.id) |> Repo.delete_all()
    from(l in Link, where: l.id == ^link.id) |> Repo.delete_all()

    case Liminal.Links.ImageDownloader.delete(link.image_path) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end
