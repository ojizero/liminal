defmodule Liminal.Accounts.Admin do
  @moduledoc """
  Admin-only user management: listing, enable/disable, delete, promote/demote,
  and self-service step-down / account deletion.
  """

  import Ecto.Query, warn: false

  alias Liminal.Repo
  alias Liminal.Accounts.{AdminCache, Scope, User}

  @doc "Lists all users ordered by username. Requires admin scope."
  def list_users(scope) do
    ensure_admin!(scope)
    Repo.all(from u in User, order_by: [asc: u.username])
  end

  @doc "Disables a user. Requires admin scope. Cannot disable admins."
  def disable_user(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)
    Repo.update(User.disable_changeset(user))
  end

  @doc "Enables a user. Requires admin scope. Cannot enable admins."
  def enable_user(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)
    Repo.update(User.enable_changeset(user))
  end

  @doc "Deletes a user. Requires admin scope. Cannot delete admins."
  def delete_user(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)
    Repo.delete(user)
  end

  @doc "Promotes a user to admin. Requires admin scope. Cannot promote existing admins."
  def promote_user(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)

    case Repo.update(User.role_changeset(user, %{role: "admin"})) do
      {:ok, promoted} ->
        AdminCache.mark_admin_exists()
        {:ok, promoted}

      error ->
        error
    end
  end

  @doc """
  Demotes an admin to a normal user. Requires admin scope.

  Returns `{:error, :self_demotion}`, `{:error, :not_admin}`, or
  `{:error, :last_admin}` when the operation is not allowed.
  """
  def demote_user(scope, user) do
    ensure_admin!(scope)

    cond do
      user.id == scope.user.id -> {:error, :self_demotion}
      user.role != "admin" -> {:error, :not_admin}
      admin_count() <= 1 -> {:error, :last_admin}
      true -> Repo.update(User.role_changeset(user, %{role: "user"}))
    end
  end

  @doc """
  Deletes the current user's own account.

  Returns `{:error, :last_admin}` if the user is the last admin.
  """
  def delete_own_account(scope) do
    user = scope.user

    cond do
      user.role == "admin" and admin_count() <= 1 -> {:error, :last_admin}
      :otherwise -> Repo.delete(user)
    end
  end

  @doc """
  Steps the current admin down to a normal user.

  Returns `{:error, :last_admin}` if the user is the last admin, or
  `{:error, :not_admin}` if the user is not an admin.
  """
  def step_down_from_admin(scope) do
    user = scope.user

    cond do
      user.role != "admin" -> {:error, :not_admin}
      admin_count() <= 1 -> {:error, :last_admin}
      true -> Repo.update(User.role_changeset(user, %{role: "user"}))
    end
  end

  @doc false
  def ensure_admin!(scope) do
    unless Scope.admin?(scope), do: raise("admin required")
  end

  @doc false
  def ensure_not_admin!(user) do
    if user.role == "admin", do: raise("cannot modify admin user")
  end

  # Not locked within a transaction — acceptable for a small app with few admins.
  defp admin_count do
    Repo.one(from u in User, where: u.role == "admin", select: count(u.id))
  end
end
