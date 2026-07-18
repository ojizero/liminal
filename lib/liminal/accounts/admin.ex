defmodule Liminal.Accounts.Admin do
  @moduledoc """
  Admin-only account lifecycle operations and admin-presence checks.
  """

  import Ecto.Query, warn: false

  alias Liminal.Accounts.{PasswordReset, Scope, User}
  alias Liminal.Repo

  @admin_cache_key {Liminal.Accounts, :has_admins}

  @doc """
  Registers the first admin user during initial instance setup.
  Only succeeds if no admin users exist yet. Raises if admins already exist.
  """
  def register_admin(attrs) do
    case any_admins?() do
      true -> raise("cannot register admin: admin users already exist")
      false -> insert_first_admin(attrs)
    end
  end

  @doc """
  Lists all users. Requires admin scope.
  """
  def list_users(scope) do
    ensure_admin!(scope)
    Repo.all(from u in User, order_by: [asc: u.username])
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for the invite user form.
  """
  def change_invite_user(attrs \\ %{}) do
    User.invite_changeset(%User{}, attrs)
  end

  @doc """
  Invites a user (admin-created, no password). Requires admin scope.

  Creates the user with username and role only, generates a reset password
  token so the invited user can set their password. Returns `{:ok, {user, encoded_token}}`.

  Also creates default tags for the new user. Rolls back
  the transaction if any step fails.
  """
  def invite_user(scope, attrs) do
    ensure_admin!(scope)

    Repo.transact(fn ->
      with {:ok, user} <- Repo.insert(User.invite_changeset(%User{}, attrs)),
           :ok <- Liminal.Links.create_default_tags(user.id) do
        encoded_token = PasswordReset.create_reset_password_token(user)
        {:ok, {user, encoded_token}}
      end
    end)
  end

  @doc """
  Disables a user. Requires admin scope. Cannot disable admins.
  """
  def disable_user(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)
    Repo.update(User.disable_changeset(user))
  end

  @doc """
  Enables a user. Requires admin scope. Cannot enable admins.
  """
  def enable_user(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)
    Repo.update(User.enable_changeset(user))
  end

  @doc """
  Deletes a user. Requires admin scope. Cannot delete admins.
  """
  def delete_user(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)
    Repo.delete(user)
  end

  @doc """
  Promotes a user to admin. Requires admin scope. Cannot promote existing admins.
  """
  def promote_user(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)

    case Repo.update(User.role_changeset(user, %{role: "admin"})) do
      {:ok, user} ->
        :persistent_term.put(@admin_cache_key, true)
        {:ok, user}

      error ->
        error
    end
  end

  @doc """
  Demotes an admin user to a normal user. Requires admin scope.
  Cannot demote yourself (use settings page) or the last admin.

  Returns `{:error, :self_demotion}` if trying to demote yourself,
  `{:error, :not_admin}` if the target is not an admin,
  or `{:error, :last_admin}` if they are the last admin.
  """
  def demote_user(scope, user) do
    ensure_admin!(scope)
    demote_admin(scope.user, user)
  end

  @doc """
  Deletes the current user's own account.

  Returns `{:error, :last_admin}` if the user is the last admin.
  """
  def delete_own_account(%Scope{user: user}) do
    delete_user_unless_last_admin(user)
  end

  @doc """
  Steps down the current admin user to a normal user.

  Returns `{:error, :last_admin}` if the user is the last admin,
  or `{:error, :not_admin}` if the user is not an admin.
  """
  def step_down_from_admin(%Scope{user: user}) do
    step_down_user(user)
  end

  @doc """
  Returns true if at least one admin user exists in the system.
  Used to determine if first-time setup is needed.
  """
  def any_admins? do
    case :persistent_term.get(@admin_cache_key, :not_set) do
      :not_set -> cache_admin_presence()
      admin? -> admin?
    end
  end

  @doc "Clears the cached admin-exists flag (used in tests)."
  def reset_admin_cache do
    :persistent_term.erase(@admin_cache_key)
  end

  @doc """
  Generates a reset password token for a user. Requires admin scope.
  Cannot generate tokens for admins.

  Deletes any existing reset password tokens for the user before
  generating a new one.

  Returns the encoded token string.
  """
  def generate_reset_password_token(scope, user) do
    ensure_admin!(scope)
    ensure_not_admin!(user)
    PasswordReset.create_reset_password_token(user, replace_existing: true)
  end

  defp insert_first_admin(attrs) do
    Repo.transact(fn ->
      with {:ok, user} <-
             %User{}
             |> User.registration_changeset(attrs)
             |> Ecto.Changeset.put_change(:role, "admin")
             |> Repo.insert(),
           :ok <- Liminal.Links.create_default_tags(user.id) do
        :persistent_term.put(@admin_cache_key, true)
        {:ok, user}
      end
    end)
  end

  defp demote_admin(%User{id: id}, %User{id: id}), do: {:error, :self_demotion}
  defp demote_admin(_admin, %User{role: role}) when role != "admin", do: {:error, :not_admin}
  defp demote_admin(_admin, user), do: update_role_unless_last_admin(user)

  defp delete_user_unless_last_admin(%User{role: "admin"} = user) do
    case last_admin?() do
      true -> {:error, :last_admin}
      false -> Repo.delete(user)
    end
  end

  defp delete_user_unless_last_admin(user), do: Repo.delete(user)

  defp step_down_user(%User{role: role}) when role != "admin", do: {:error, :not_admin}
  defp step_down_user(user), do: update_role_unless_last_admin(user)

  defp update_role_unless_last_admin(user) do
    case last_admin?() do
      true -> {:error, :last_admin}
      false -> Repo.update(User.role_changeset(user, %{role: "user"}))
    end
  end

  # Not locked within a transaction; this preserves the previous small-app tradeoff.
  defp last_admin?, do: admin_count() <= 1

  defp admin_count do
    Repo.one(from u in User, where: u.role == "admin", select: count(u.id))
  end

  defp cache_admin_presence do
    admin? = Repo.exists?(from u in User, where: u.role == "admin")

    if admin? do
      :persistent_term.put(@admin_cache_key, true)
    end

    admin?
  end

  defp ensure_admin!(scope) do
    unless Scope.admin?(scope), do: raise("admin required")
  end

  defp ensure_not_admin!(%User{role: "admin"}), do: raise("cannot modify admin user")
  defp ensure_not_admin!(%User{}), do: :ok
end
