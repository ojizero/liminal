defmodule Liminal.Links.Stats do
  @moduledoc """
  Instance-wide and per-user link statistics for dashboards.

  Expiring-soon thresholds are fixed here so UI and admin reports stay consistent.
  """

  import Ecto.Query

  alias Liminal.Accounts.Scope
  alias Liminal.Accounts.User
  alias Liminal.Links.Link
  alias Liminal.Links.LinkTag
  alias Liminal.Repo

  @expiring_soon_hours 48
  @about_to_expire_days 7

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
    %{
      total_links: count_links(nil),
      unviewed_links: count_links(nil, :unviewed),
      viewed_links: count_links(nil, :viewed),
      expiring_soon: count_expiring(nil, :soon),
      about_to_expire: count_expiring(nil, :about),
      index_failed: count_index_failed(nil),
      top_domains: top_domains(nil, 5)
    }
  end

  def user_stats(user_id) when is_binary(user_id) do
    %{
      total_links: count_links(user_id),
      unviewed_links: count_links(user_id, :unviewed),
      viewed_links: count_links(user_id, :viewed),
      expiring_soon: count_expiring(user_id, :soon),
      about_to_expire: count_expiring(user_id, :about),
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

  defp count_expiring(user_id, :soon) do
    count_expiring_between(user_id, expiring_soon_window())
  end

  defp count_expiring(user_id, :about) do
    count_expiring_between(user_id, about_to_expire_window())
  end

  defp count_expiring_between(user_id, {now, cutoff}) do
    grace_seconds = viewed_grace_seconds()

    expiry_sub =
      from(lt in LinkTag,
        group_by: lt.link_id,
        select: %{link_id: lt.link_id, max_expiry: max(lt.expires_at)}
      )

    user_id
    |> link_query()
    |> join(:left, [l], e in subquery(expiry_sub), on: e.link_id == l.id)
    |> where(
      [l, e],
      (not is_nil(l.viewed_at) and
         fragment("datetime(?, '+' || ? || ' seconds')", l.viewed_at, ^grace_seconds) > ^now and
         fragment("datetime(?, '+' || ? || ' seconds')", l.viewed_at, ^grace_seconds) <= ^cutoff) or
        (is_nil(l.viewed_at) and not is_nil(e.max_expiry) and e.max_expiry > ^now and
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

  defp expiring_soon_window do
    now = DateTime.utc_now(:second)
    {now, DateTime.add(now, @expiring_soon_hours, :hour)}
  end

  defp about_to_expire_window do
    now = DateTime.utc_now(:second)
    {now, DateTime.add(now, @about_to_expire_days, :day)}
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
