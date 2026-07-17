defmodule Liminal.Accounts do
  @moduledoc """
  Public façade for the Accounts domain.

  All implementation lives in focused sub-modules:

    * `Liminal.Accounts.Registration` — sign-up, first-admin bootstrap, invite
    * `Liminal.Accounts.Credentials`  — sudo mode, username/password/settings
    * `Liminal.Accounts.Sessions`     — session token lifecycle
    * `Liminal.Accounts.ResetPasswords` — admin-issued reset tokens
    * `Liminal.Accounts.Admin`        — user management (enable/disable/promote…)
    * `Liminal.Accounts.AdminCache`   — persistent-term cache for admin-exists flag

  This module re-exports every public function so callers keep a stable API.
  """

  import Ecto.Query, warn: false

  alias Liminal.Repo

  alias Liminal.Accounts.{
    Admin,
    AdminCache,
    Credentials,
    Registration,
    ResetPasswords,
    Sessions,
    User
  }

  ## Configuration

  @doc "Returns whether public signups are enabled via configuration."
  def signups_enabled? do
    Application.get_env(:liminal, :signups_enabled, false)
  end

  ## Database getters

  @doc "Returns a user by username or `nil`."
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Returns the user when credentials match. Disabled accounts always return `nil`.
  """
  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username)

    cond do
      is_nil(user) -> nil
      not is_nil(user.disabled_at) -> nil
      User.valid_password?(user, password) -> user
      true -> nil
    end
  end

  @doc "Fetches a user by id and raises when missing."
  def get_user!(id), do: Repo.get!(User, id)

  ## Registration — delegates to Liminal.Accounts.Registration

  defdelegate register_user(attrs), to: Registration
  defdelegate register_admin(attrs), to: Registration
  defdelegate invite_user(scope, attrs), to: Registration

  @doc "Registration changeset for forms — skips password hashing for live validation."
  def change_user_registration(user, attrs \\ %{}),
    do: Registration.change_user_registration(user, attrs)

  @doc "Returns an `%Ecto.Changeset{}` for the invite user form."
  def change_invite_user(attrs \\ %{}),
    do: Registration.change_invite_user(attrs)

  ## Credentials — delegates to Liminal.Accounts.Credentials

  defdelegate update_user_username(user, attrs), to: Credentials
  defdelegate update_user_password(user, attrs), to: Credentials
  defdelegate update_user_settings(user, attrs), to: Credentials

  @doc """
  Returns `true` if the user authenticated within `minutes` minutes.
  Default window is 20 minutes.
  """
  def sudo_mode?(user, minutes \\ -20),
    do: Credentials.sudo_mode?(user, minutes)

  @doc "Returns a username changeset for forms."
  def change_user_username(user, attrs \\ %{}, opts \\ []),
    do: Credentials.change_user_username(user, attrs, opts)

  @doc "Returns a password changeset for forms."
  def change_user_password(user, attrs \\ %{}, opts \\ []),
    do: Credentials.change_user_password(user, attrs, opts)

  @doc "Returns a settings changeset for user preferences."
  def change_user_settings(user, attrs \\ %{}),
    do: Credentials.change_user_settings(user, attrs)

  ## Sessions — delegates to Liminal.Accounts.Sessions

  defdelegate generate_user_session_token(user), to: Sessions
  defdelegate get_user_by_session_token(token), to: Sessions
  defdelegate delete_user_session_token(token), to: Sessions

  ## Admin — delegates to Liminal.Accounts.Admin

  defdelegate list_users(scope), to: Admin
  defdelegate disable_user(scope, user), to: Admin
  defdelegate enable_user(scope, user), to: Admin
  defdelegate delete_user(scope, user), to: Admin
  defdelegate promote_user(scope, user), to: Admin
  defdelegate demote_user(scope, user), to: Admin
  defdelegate delete_own_account(scope), to: Admin
  defdelegate step_down_from_admin(scope), to: Admin

  ## AdminCache — delegates to Liminal.Accounts.AdminCache

  defdelegate any_admins?(), to: AdminCache
  defdelegate reset_admin_cache(), to: AdminCache

  ## ResetPasswords — delegates to Liminal.Accounts.ResetPasswords

  defdelegate generate_reset_password_token(scope, user), to: ResetPasswords
  defdelegate get_user_by_reset_password_token(encoded_token), to: ResetPasswords
  defdelegate reset_user_password(user, attrs), to: ResetPasswords

  @doc "Returns a password changeset for the reset-password form."
  def change_reset_password(user, attrs \\ %{}),
    do: ResetPasswords.change_reset_password(user, attrs)
end
