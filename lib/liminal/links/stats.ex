defmodule Liminal.Links.Stats do
  @moduledoc """
  Instance-wide and per-user link statistics for dashboards.

  Expiring-soon thresholds are fixed here so UI and admin reports stay consistent.
  """

  import Ecto.Query

  alias Liminal.Accounts.Scope
  alias Liminal.Accounts.User
  alias Liminal.Links.ExpiryPause
  alias Liminal.Links.Link
  alias Liminal.Links.LinkTag
  alias Liminal.Repo

  @expiring_soon_seconds 48 * 60 * 60
  @about_to_expire_seconds 7 * 24 * 60 * 60

  @doc """
  Returns comprehensive stats across the whole instance.
  """
  def instance_stats do
    user_stats(nil)
    |> Map.merge(%{
      total_users: count_users(),
      index_pending: count_index_pending(nil),
      index_gave_up: count_index_gave_up(nil)
    })
  end

  @doc """
  Returns a subset of stats scoped to the given user.
  """
  def user_stats(%Scope{} = scope) do
    user_stats(scope.user.id)
  end

  def user_stats(nil) do
    scoped_stats(nil)
  end

  def user_stats(user_id) when is_binary(user_id) do
    scoped_stats(user_id)
  end

  defp scoped_stats(user_id) do
    now = DateTime.utc_now(:second)

    %{
      total_links: count_links(user_id),
      unviewed_links: count_links(user_id, :unviewed),
      viewed_links: count_links(user_id, :viewed),
      expiring_soon: count_expiring(user_id, now, @expiring_soon_seconds),
      about_to_expire: count_expiring(user_id, now, @about_to_expire_seconds),
      index_failed: count_index_failed(user_id),
      top_domains: top_domains(user_id, 5)
    }
  end

  defp count_users do
    Repo.aggregate(User, :count)
  end

  defp count_links(user_id, filter \\ :all)

  defp count_links(user_id, filter) do
    user_id
    |> link_query()
    |> apply_filter(filter)
    |> Repo.aggregate(:count)
  end

  defp count_index_pending(user_id) do
    user_id
    |> link_query()
    |> where([l], is_nil(l.indexed_at) and is_nil(l.index_gave_up_at))
    |> Repo.aggregate(:count)
  end

  defp count_index_gave_up(user_id) do
    user_id
    |> link_query()
    |> where([l], not is_nil(l.index_gave_up_at))
    |> Repo.aggregate(:count)
  end

  defp count_index_failed(user_id) do
    user_id
    |> link_query()
    |> where(
      [l],
      is_nil(l.indexed_at) and
        (not is_nil(l.index_gave_up_at) or l.index_attempt_count > 0)
    )
    |> Repo.aggregate(:count)
  end

  # Deadlines are stored on the expiry clock (see `Liminal.Links.ExpiryPause`), so a
  # per-user window is read on that clock too. Instance-wide counts have no single
  # clock to read, and instead leave out users whose expiries are on hold.
  defp count_expiring(nil, now, seconds) do
    from(l in Link)
    |> ExpiryPause.exclude_paused_links(now)
    |> count_expiring_between(now, DateTime.add(now, seconds, :second))
  end

  defp count_expiring(user_id, now, seconds) do
    expiry_now = ExpiryPause.expiry_now(user_id, now)

    user_id
    |> link_query()
    |> count_expiring_between(expiry_now, DateTime.add(expiry_now, seconds, :second))
  end

  defp count_expiring_between(query, from_time, cutoff) do
    # The viewed grace is a fixed offset, so it is folded into the bounds instead of
    # doing date arithmetic in SQL, where the result would not compare against the
    # stored ISO-8601 text.
    grace_seconds = viewed_grace_seconds()
    viewed_from = DateTime.add(from_time, -grace_seconds, :second)
    viewed_cutoff = DateTime.add(cutoff, -grace_seconds, :second)

    expiry_sub =
      from(lt in LinkTag,
        group_by: lt.link_id,
        select: %{link_id: lt.link_id, max_expiry: max(lt.expires_at)}
      )

    query
    |> join(:left, [l], e in subquery(expiry_sub), on: e.link_id == l.id)
    |> where(
      [l, ..., e],
      (not is_nil(l.viewed_at) and l.viewed_at > ^viewed_from and
         l.viewed_at <= ^viewed_cutoff) or
        (is_nil(l.viewed_at) and not is_nil(e.max_expiry) and e.max_expiry > ^from_time and
           e.max_expiry <= ^cutoff)
    )
    |> Repo.aggregate(:count)
  end

  defp top_domains(user_id, limit) do
    user_id
    |> link_query()
    |> select([l], l.url)
    |> Repo.all()
    |> Enum.map(&url_host/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_host, count} -> count end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {host, count} -> %{host: host, count: count} end)
  end

  defp link_query(nil), do: from(l in Link)

  defp link_query(user_id), do: from(l in Link, where: l.user_id == ^user_id)

  defp apply_filter(query, :all), do: query

  defp apply_filter(query, :unviewed) do
    from(l in query, where: is_nil(l.viewed_at))
  end

  defp apply_filter(query, :viewed) do
    from(l in query, where: not is_nil(l.viewed_at))
  end

  defp viewed_grace_seconds do
    Application.get_env(:liminal, :viewed_grace_seconds, 86_400)
  end

  defp url_host(url) when is_binary(url) do
    case URI.parse(url).host do
      host when is_binary(host) and host != "" -> String.downcase(host)
      _ -> "unknown"
    end
  end
end
