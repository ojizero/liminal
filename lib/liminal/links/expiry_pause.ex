defmodule Liminal.Links.ExpiryPause do
  @moduledoc """
  Pausing and resuming a user's expiry countdowns.

  ## The expiry clock

  Stored deadlines (`link_tags.expires_at` and `links.viewed_at`) sit on an
  *expiry clock* rather than on the wall clock. The two run together except while
  a pause is in effect: then the expiry clock stands still at `expiry_paused_at`
  while the wall clock keeps moving. The gap between them is the pause shift.

  Reads convert a stored deadline to wall clock by adding the shift; writes go the
  other way and subtract it. Nothing expires while a user is paused, and when the
  pause ends every stored deadline for that user moves forward by the shift, so
  each link picks up with exactly the time it had left when it stopped counting.

  A pause window always ends on its own: the sweep in `Liminal.Links.Expiration`
  settles lapsed pauses before it deletes anything. See `max_pause_days/0` for the cap.
  """

  import Ecto.Query

  require Logger

  alias Liminal.Accounts
  alias Liminal.Accounts.Scope
  alias Liminal.Accounts.User
  alias Liminal.Links.{Events, Link, LinkTag}
  alias Liminal.Repo

  @max_pause_days 90
  @default_pause_days 14

  # SQLite stores `:utc_datetime` as ISO-8601 text, and `datetime()` would write it
  # back without the `T`/`Z`, leaving the column with two formats that no longer sort
  # against each other. `strftime` with an explicit format keeps it byte-identical.
  @shift_sql "strftime('%Y-%m-%dT%H:%M:%SZ', ?, ?)"

  @duration_options [
    {"1 day", 1},
    {"3 days", 3},
    {"1 week", 7},
    {"2 weeks", 14},
    {"1 month", 30},
    {"2 months", 60},
    {"3 months", 90}
  ]

  @doc "Longest pause a user may request, in days."
  def max_pause_days, do: @max_pause_days

  @doc "Pause length preselected in the settings form, in days."
  def default_pause_days, do: @default_pause_days

  @doc "Pause lengths offered in the settings form as `{label, days}` pairs."
  def duration_options, do: @duration_options

  @doc """
  Returns the pause window as `%{paused_at: _, paused_until: _}`, or `nil` when the
  user is not on a pause. Accepts a scope, a user, an already-built state, or `nil`.
  """
  def state(%Scope{user: user}), do: state(user)

  def state(%User{expiry_paused_at: paused_at, expiry_paused_until: paused_until}) do
    build_state(paused_at, paused_until)
  end

  def state(%{paused_at: paused_at, paused_until: paused_until}) do
    build_state(paused_at, paused_until)
  end

  def state(nil), do: nil

  @doc """
  Returns whether expiries are currently held for the given scope, user, or state.

  A window whose end has passed but that the sweep has not settled yet counts as
  no longer paused — the countdowns have already started moving again.
  """
  def paused?(subject, now \\ DateTime.utc_now(:second)) do
    case state(subject) do
      nil -> false
      %{paused_until: paused_until} -> DateTime.compare(paused_until, now) == :gt
    end
  end

  @doc "Returns when the pause ends, or `nil` when there is no pause."
  def resumes_at(subject) do
    case state(subject) do
      nil -> nil
      %{paused_until: paused_until} -> paused_until
    end
  end

  @doc """
  Returns how far the expiry clock currently lags the wall clock, in seconds.

  This is the pause time not yet folded into the stored deadlines. It grows while a
  pause runs, stops growing once the window ends, and drops back to zero when the
  pause is settled.
  """
  def shift_seconds(subject, now \\ DateTime.utc_now(:second)) do
    case state(subject) do
      nil ->
        0

      %{paused_at: paused_at, paused_until: paused_until} ->
        paused_until
        |> earliest(now)
        |> DateTime.diff(paused_at)
        |> max(0)
    end
  end

  @doc """
  Converts a stored expiry-clock deadline to the wall-clock time it now falls on.
  """
  def wall_clock(nil, _subject), do: nil

  def wall_clock(%DateTime{} = expires_at, subject) do
    DateTime.add(expires_at, shift_seconds(subject), :second)
  end

  @doc """
  Returns the expiry-clock reading for a user, used when writing new deadlines.

  Reads the pause straight from the database so a deadline is never written against
  a stale copy of the user carried on a long-lived socket.
  """
  def expiry_now(user_id, now \\ DateTime.utc_now(:second)) when is_binary(user_id) do
    DateTime.add(now, -shift_seconds(load_state(user_id), now), :second)
  end

  @doc """
  Starts a pause of `days` for the scope's user, or re-times a pause already running.

  Re-timing measures from the existing pause start, so picking a longer or shorter
  length moves the end date rather than restarting the pause. A length shorter than
  the time already spent paused resumes immediately.
  """
  def pause(%Scope{} = scope, days) do
    with {:ok, days} <- validate_days(days),
         now = DateTime.utc_now(:second),
         user = Repo.get!(User, scope.user.id),
         {:ok, user} <- settle_if_lapsed(user, now) do
      paused_at = user.expiry_paused_at || now
      paused_until = DateTime.add(paused_at, days, :day)

      case DateTime.compare(paused_until, now) do
        :gt -> user |> write_pause(paused_at, paused_until) |> announce()
        _ -> user |> settle(now) |> announce()
      end
    end
  end

  @doc """
  Ends the scope user's pause now, folding the paused time into every stored deadline.

  Returns the updated user. A user who is not paused is returned untouched.
  """
  def resume(%Scope{} = scope) do
    User
    |> Repo.get!(scope.user.id)
    |> settle(DateTime.utc_now(:second))
    |> announce()
  end

  @doc """
  Settles every pause whose window has run out.

  Called at the start of each expiry sweep so no user is swept while their stored
  deadlines still owe them paused time.
  """
  def settle_lapsed_pauses(now \\ DateTime.utc_now(:second)) do
    from(u in User, where: not is_nil(u.expiry_paused_until) and u.expiry_paused_until <= ^now)
    |> Repo.all()
    |> Enum.each(&settle_lapsed_pause(&1, now))
  end

  @doc """
  Ends `user`'s pause, folding the time it ran for into their stored deadlines.

  Takes a user rather than a scope so the sweep can settle in bulk. Safe to call with
  a copy loaded before another caller got to it: the window is claimed before any
  deadline moves, so two callers racing the same window still shift it once.
  """
  def settle(user, now \\ DateTime.utc_now(:second))

  def settle(%User{expiry_paused_at: nil} = user, _now), do: {:ok, user}

  def settle(%User{} = user, now) do
    shift = shift_seconds(user, now)

    Repo.transact(fn ->
      case Accounts.clear_expiry_pause(user) do
        :ok ->
          shift_stored_deadlines(user.id, shift)
          {:ok, %User{user | expiry_paused_at: nil, expiry_paused_until: nil}}

        :already_cleared ->
          {:ok, Repo.get!(User, user.id)}
      end
    end)
  end

  @doc """
  Restricts a link query to users whose expiries are running.

  Expects a query aliased on `Link` as its first binding.
  """
  def exclude_paused_links(query, now) do
    from(l in query,
      join: u in User,
      on: u.id == l.user_id,
      where: is_nil(u.expiry_paused_until) or u.expiry_paused_until <= ^now
    )
  end

  defp build_state(nil, _paused_until), do: nil
  defp build_state(_paused_at, nil), do: nil

  defp build_state(paused_at, paused_until) do
    %{paused_at: paused_at, paused_until: paused_until}
  end

  defp load_state(user_id) do
    from(u in User,
      where: u.id == ^user_id,
      select: %{paused_at: u.expiry_paused_at, paused_until: u.expiry_paused_until}
    )
    |> Repo.one()
    |> state()
  end

  defp validate_days(days) when is_integer(days) and days >= 1 and days <= @max_pause_days do
    {:ok, days}
  end

  defp validate_days(_days), do: {:error, :invalid_duration}

  defp write_pause(user, paused_at, paused_until) do
    Accounts.update_expiry_pause(user, %{
      expiry_paused_at: paused_at,
      expiry_paused_until: paused_until
    })
  end

  # A window that has already run out is settled on its own terms before anything is
  # built on top of it, so its time lands in the stored deadlines rather than being
  # rolled into a new window.
  defp settle_if_lapsed(%User{expiry_paused_until: nil} = user, _now), do: {:ok, user}

  defp settle_if_lapsed(%User{} = user, now) do
    case DateTime.compare(user.expiry_paused_until, now) do
      :gt -> {:ok, user}
      _ -> settle(user, now)
    end
  end

  defp settle_lapsed_pause(user, now) do
    case settle(user, now) do
      {:ok, settled} ->
        Events.broadcast_expiry_pause_changed(settled)

      {:error, reason} ->
        Logger.warning("Links: failed to settle expiry pause for #{user.id}: #{inspect(reason)}")
    end
  end

  defp shift_stored_deadlines(_user_id, 0), do: :ok

  defp shift_stored_deadlines(user_id, seconds) do
    offset = "+#{seconds} seconds"
    user_link_ids = from(l in Link, where: l.user_id == ^user_id, select: l.id)

    from(lt in LinkTag,
      where: lt.link_id in subquery(user_link_ids) and not is_nil(lt.expires_at),
      update: [set: [expires_at: fragment(@shift_sql, lt.expires_at, ^offset)]]
    )
    |> Repo.update_all([])

    from(l in Link,
      where: l.user_id == ^user_id and not is_nil(l.viewed_at),
      update: [set: [viewed_at: fragment(@shift_sql, l.viewed_at, ^offset)]]
    )
    |> Repo.update_all([])

    :ok
  end

  defp announce({:ok, user}) do
    Events.broadcast_expiry_pause_changed(user)
    {:ok, user}
  end

  defp announce({:error, reason}), do: {:error, reason}

  defp earliest(a, b) do
    case DateTime.compare(a, b) do
      :gt -> b
      _ -> a
    end
  end
end
