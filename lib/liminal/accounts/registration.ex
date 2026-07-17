defmodule Liminal.Accounts.Registration do
  @moduledoc """
  User registration flows: public sign-up, first-admin bootstrap, and admin-invite.
  """

  alias Liminal.Repo
  alias Liminal.Accounts.{Admin, AdminCache, User, UserToken}

  @doc "Registers a user and creates their default tags in one transaction."
  def register_user(attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.insert(User.registration_changeset(%User{}, attrs)),
           :ok <- Liminal.Links.create_default_tags(user.id) do
        {:ok, user}
      end
    end)
  end

  @doc """
  Registers the first admin user during initial instance setup.

  Raises if any admin already exists.
  """
  def register_admin(attrs) do
    if AdminCache.any_admins?(), do: raise("cannot register admin: admin users already exist")

    Repo.transact(fn ->
      with {:ok, user} <-
             %User{}
             |> User.registration_changeset(attrs)
             |> Ecto.Changeset.put_change(:role, "admin")
             |> Repo.insert(),
           :ok <- Liminal.Links.create_default_tags(user.id) do
        AdminCache.mark_admin_exists()
        {:ok, user}
      end
    end)
  end

  @doc "Registration changeset for forms — skips password hashing for live validation."
  def change_user_registration(user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  @doc "Returns an `%Ecto.Changeset{}` for the invite user form."
  def change_invite_user(attrs \\ %{}) do
    User.invite_changeset(%User{}, attrs)
  end

  @doc """
  Invites a user (admin-created, no password). Requires admin scope.

  Creates the user with username and role, generates a reset-password token so
  the invited user can set their password. Also creates default tags.

  Returns `{:ok, {user, encoded_token}}`.
  """
  def invite_user(scope, attrs) do
    Admin.ensure_admin!(scope)

    Repo.transact(fn ->
      with {:ok, user} <- Repo.insert(User.invite_changeset(%User{}, attrs)),
           :ok <- Liminal.Links.create_default_tags(user.id) do
        {encoded_token, user_token} = UserToken.build_reset_password_token(user)
        Repo.insert!(user_token)
        {:ok, {user, encoded_token}}
      end
    end)
  end
end
