defmodule Liminal.Accounts.AdminCache do
  @moduledoc """
  Persistent-term cache for the "at least one admin exists" flag.

  Reads hit the in-process store; the flag is set on first admin creation
  and cleared only by `reset_admin_cache/0` (used in tests).
  """

  import Ecto.Query, warn: false

  alias Liminal.Repo
  alias Liminal.Accounts.User

  @cache_key {Liminal.Accounts, :has_admins}

  @doc """
  Returns `true` if at least one admin user exists.

  The result is cached in persistent-term after the first DB hit so that
  subsequent calls within the same node lifetime are O(1).
  """
  def any_admins? do
    with :not_set <- :persistent_term.get(@cache_key, :not_set) do
      Repo.exists?(from u in User, where: u.role == "admin")
      |> tap(fn
        true -> :persistent_term.put(@cache_key, true)
        false -> :noop
      end)
    end
  end

  @doc "Marks the admin-exists flag as true without a DB query."
  def mark_admin_exists do
    :persistent_term.put(@cache_key, true)
  end

  @doc "Clears the cached admin-exists flag. Used in tests."
  def reset_admin_cache do
    :persistent_term.erase(@cache_key)
  end
end
