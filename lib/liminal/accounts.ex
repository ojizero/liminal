defmodule Liminal.Accounts do
  @moduledoc """
  User accounts, authentication, sessions, and admin-only user management.
  """

  import Ecto.Query

  alias Liminal.Repo

  alias Liminal.Accounts.{Admin, PasswordReset, Sessions, User}

  @doc """
  Returns whether public signups are enabled via configuration.
  """
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

  ## User registration

  @doc """
  Registers a user and creates their default tags in one transaction.
  """
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
  Only succeeds if no admin users exist yet. Raises if admins already exist.
  """
  defdelegate register_admin(attrs), to: Admin

  @doc """
  Registration changeset for forms — skips password hashing so live validation stays fast.
  """
  def change_user_registration(user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc "Returns a username changeset for forms."
  def change_user_username(user, attrs \\ %{}, opts \\ []) do
    User.username_changeset(user, attrs, opts)
  end

  @doc "Updates a user's username."
  def update_user_username(user, attrs) do
    user
    |> User.username_changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns a password changeset for forms."
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the password and invalidates all existing session tokens.
  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Sessions.update_user_and_delete_all_tokens()
  end

  @doc "Returns a settings changeset for user preferences."
  def change_user_settings(user, attrs \\ %{}) do
    User.settings_changeset(user, attrs)
  end

  @doc "Updates user preference settings."
  def update_user_settings(user, attrs) do
    user
    |> User.settings_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Writes the user's expiry pause window.

  Callers should go through `Liminal.Links.pause_expiries/2` and
  `Liminal.Links.resume_expiries/1` so the stored expiry deadlines stay in step
  with the pause.
  """
  def update_expiry_pause(user, attrs) do
    user
    |> User.expiry_pause_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Clears the user's expiry pause, but only while it still starts where `user` says.

  Returns `:ok` for the caller that cleared it and `:already_cleared` when another
  caller got there first. Ending a pause also shifts stored deadlines, so this lets
  a manual resume racing the expiry sweep apply that shift exactly once.
  """
  def clear_expiry_pause(%User{expiry_paused_at: paused_at} = user) do
    {cleared, _} =
      from(u in User, where: u.id == ^user.id and u.expiry_paused_at == ^paused_at)
      |> Repo.update_all(
        set: [
          expiry_paused_at: nil,
          expiry_paused_until: nil,
          updated_at: DateTime.utc_now(:second)
        ]
      )

    case cleared do
      1 -> :ok
      0 -> :already_cleared
    end
  end

  ## Session

  @doc "Creates and persists a session token."
  defdelegate generate_user_session_token(user), to: Sessions

  @doc """
  Returns `{user, token_inserted_at}` when the session token is valid, else `nil`.
  """
  defdelegate get_user_by_session_token(token), to: Sessions

  @doc "Deletes a persisted session token."
  defdelegate delete_user_session_token(token), to: Sessions

  ## Admin functions

  @doc """
  Lists all users. Requires admin scope.
  """
  defdelegate list_users(scope), to: Admin

  @doc """
  Returns an `%Ecto.Changeset{}` for the invite user form.
  """
  defdelegate change_invite_user(attrs \\ %{}), to: Admin

  @doc """
  Invites a user (admin-created, no password). Requires admin scope.

  Creates the user with username and role only, generates a reset password
  token so the invited user can set their password. Returns `{:ok, {user, encoded_token}}`.

  Also creates default tags for the new user. Rolls back
  the transaction if any step fails.
  """
  defdelegate invite_user(scope, attrs), to: Admin

  @doc """
  Disables a user. Requires admin scope. Cannot disable admins.
  """
  defdelegate disable_user(scope, user), to: Admin

  @doc """
  Enables a user. Requires admin scope. Cannot enable admins.
  """
  defdelegate enable_user(scope, user), to: Admin

  @doc """
  Deletes a user. Requires admin scope. Cannot delete admins.
  """
  defdelegate delete_user(scope, user), to: Admin

  @doc """
  Promotes a user to admin. Requires admin scope. Cannot promote existing admins.
  """
  defdelegate promote_user(scope, user), to: Admin

  @doc """
  Demotes an admin user to a normal user. Requires admin scope.
  Cannot demote yourself (use settings page) or the last admin.

  Returns `{:error, :self_demotion}` if trying to demote yourself,
  `{:error, :not_admin}` if the target is not an admin,
  or `{:error, :last_admin}` if they are the last admin.
  """
  defdelegate demote_user(scope, user), to: Admin

  @doc """
  Deletes the current user's own account.

  Returns `{:error, :last_admin}` if the user is the last admin.
  """
  defdelegate delete_own_account(scope), to: Admin

  @doc """
  Steps down the current admin user to a normal user.

  Returns `{:error, :last_admin}` if the user is the last admin,
  or `{:error, :not_admin}` if the user is not an admin.
  """
  defdelegate step_down_from_admin(scope), to: Admin

  @doc """
  Returns true if at least one admin user exists in the system.
  Used to determine if first-time setup is needed.
  """
  defdelegate any_admins?(), to: Admin

  @doc "Clears the cached admin-exists flag (used in tests)."
  defdelegate reset_admin_cache(), to: Admin

  @doc """
  Generates a reset password token for a user. Requires admin scope.
  Cannot generate tokens for admins.

  Deletes any existing reset password tokens for the user before
  generating a new one.

  Returns the encoded token string.
  """
  defdelegate generate_reset_password_token(scope, user), to: Admin

  @doc """
  Gets the user with the given reset password token.

  Returns the user if the token is valid and the user is not disabled,
  otherwise returns `nil`.
  """
  defdelegate get_user_by_reset_password_token(encoded_token), to: PasswordReset

  @doc """
  Resets the user password using a reset password token flow.

  Deletes all tokens for the user after a successful password reset.
  """
  defdelegate reset_user_password(user, attrs), to: PasswordReset

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password via reset.
  """
  defdelegate change_reset_password(user, attrs \\ %{}), to: PasswordReset
end
