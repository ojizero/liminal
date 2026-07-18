defmodule Liminal.Links.Expiration do
  @moduledoc """
  Link expiration calculation and cleanup sweeps.
  """

  import Ecto.Query

  require Logger

  alias Liminal.Links.{Events, Link, LinkTag, Tagging}
  alias Liminal.Repo

  @default_viewed_grace_seconds 86_400

  @doc """
  Returns when a link expires.
  """
  def link_expires_at(%Link{viewed_at: viewed_at}) when not is_nil(viewed_at) do
    DateTime.add(viewed_at, viewed_grace_seconds(), :second)
  end

  def link_expires_at(%Link{} = link) do
    link.link_tags
    |> Enum.map(& &1.expires_at)
    |> Enum.reject(&is_nil/1)
    |> latest_expiry()
  end

  @doc """
  Deletes stale viewed links, expired link_tags, and orphaned links.
  """
  def cleanup_expired do
    now = DateTime.utc_now(:second)

    now
    |> stale_viewed_link_ids()
    |> Enum.each(&cleanup_viewed_link/1)

    now
    |> expired_link_tag_ids()
    |> Enum.each(&Tagging.cleanup_link/1)

    :ok
  end

  defp latest_expiry([]), do: nil
  defp latest_expiry(expiries), do: Enum.max(expiries, DateTime)

  defp stale_viewed_link_ids(now) do
    viewed_cutoff = viewed_expiry_cutoff(now)

    from(l in Link,
      where: not is_nil(l.viewed_at) and l.viewed_at <= ^viewed_cutoff,
      select: l.id
    )
    |> Repo.all()
  end

  defp expired_link_tag_ids(now) do
    from(lt in LinkTag,
      where: not is_nil(lt.expires_at) and lt.expires_at <= ^now,
      select: lt.id
    )
    |> Repo.all()
  end

  defp viewed_expiry_cutoff(now) do
    DateTime.add(now, -viewed_grace_seconds(), :second)
  end

  defp viewed_grace_seconds do
    Application.get_env(:liminal, :viewed_grace_seconds, @default_viewed_grace_seconds)
  end

  defp cleanup_viewed_link(link_id) do
    Link
    |> Repo.get(link_id)
    |> cleanup_viewed_link_record()
  end

  defp cleanup_viewed_link_record(nil), do: :ok

  defp cleanup_viewed_link_record(%Link{} = link) do
    with {:ok, _} <- Repo.transaction(fn -> delete_viewed_link_records(link) end) do
      Events.broadcast_link_deleted(link.user_id, link.id)
      :ok
    else
      {:error, reason} ->
        message = "failed to delete viewed link #{link.id} (#{link.url}): #{inspect(reason)}"
        Logger.warning("Links: #{message}")
        {:error, message}
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
end
