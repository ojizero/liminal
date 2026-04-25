defmodule Liminal.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Liminal.Repo

  alias Liminal.Accounts.{Scope, User, UserToken}

  ## Database getters

  @doc """
  Gets a user by username.

  ## Examples

      iex> get_user_by_username("johndoe")
      %User{}

      iex> get_user_by_username("unknown")
      nil

  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Gets a user by username and password.

  ## Examples

      iex> get_user_by_username_and_password("johndoe", "correct_password")
      %User{}

      iex> get_user_by_username_and_password("johndoe", "invalid_password")
      nil

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

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

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
  Returns an `%Ecto.Changeset{}` for changing the user registration.

  This is used for form initialization and live validation, avoiding bcrypt hashing on keystroke.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

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

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user username.

  See `Liminal.Accounts.User.username_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_username(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_username(user, attrs \\ %{}, opts \\ []) do
    User.username_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user username.

  ## Examples

      iex> update_user_username(user, %{username: "newname"})
      {:ok, %User{}}

      iex> update_user_username(user, %{username: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_username(user, attrs) do
    user
    |> User.username_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Liminal.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Admin functions

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
        {encoded_token, user_token} = UserToken.build_reset_password_token(user)
        Repo.insert!(user_token)
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
    Repo.update(User.role_changeset(user, %{role: "admin"}))
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

    if user.role == "admin" and admin_count() <= 1 do
      {:error, :last_admin}
    else
      Repo.delete(user)
    end
  end

  @doc """
  Steps down the current admin user to a normal user.

  Returns `{:error, :last_admin}` if the user is the last admin,
  or `{:error, :not_admin}` if the user is not an admin.
  """
  def step_down_from_admin(scope) do
    user = scope.user

    cond do
      user.role != "admin" -> {:error, :not_admin}
      admin_count() <= 1 -> {:error, :last_admin}
      true -> Repo.update(User.role_changeset(user, %{role: "user"}))
    end
  end

  # Counts the number of admin users in the system.
  # Note: not locked within a transaction — concurrent step-down/delete
  # could leave zero admins. Acceptable for a small app with few admins.
  defp admin_count do
    Repo.one(from u in User, where: u.role == "admin", select: count(u.id))
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

    Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
    {encoded_token, user_token} = UserToken.build_reset_password_token(user)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Gets the user with the given reset password token.

  Returns the user if the token is valid and the user is not disabled,
  otherwise returns `nil`.
  """
  def get_user_by_reset_password_token(encoded_token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(encoded_token) do
      Repo.one(query)
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password using a reset password token flow.

  Deletes all tokens for the user after a successful password reset.
  """
  def reset_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password via reset.
  """
  def change_reset_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  defp ensure_admin!(scope) do
    unless Scope.admin?(scope), do: raise("admin required")
  end

  defp ensure_not_admin!(user) do
    if user.role == "admin", do: raise("cannot modify admin user")
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
