defmodule Liminal.Accounts.User do
  use Liminal.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :role, :string, default: "user"
    field :disabled_at, :utc_datetime
    field :confirmed_at, :utc_datetime
    field :auto_mark_viewed_on_open, :boolean, default: false
    field :default_tags_enabled, :boolean, default: false
    field :authenticated_at, :utc_datetime, virtual: true

    belongs_to :default_tag, Liminal.Links.Tag

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering or changing the username.

  It requires the username to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the username, useful when displaying live validations.
      Defaults to `true`.
  """
  def username_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username])
    |> validate_username(opts)
  end

  defp validate_username(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:username])
      |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
        message: "only letters, numbers, and underscores allowed"
      )
      |> validate_length(:username, min: 3, max: 30)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:username, Liminal.Repo)
      |> unique_constraint(:username)
      |> validate_username_changed()
    else
      changeset
    end
  end

  defp validate_username_changed(changeset) do
    if get_field(changeset, :username) && get_change(changeset, :username) == nil do
      add_error(changeset, :username, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  A user changeset for registration.

  It validates username, password, and confirms the account.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> username_changeset(attrs, opts)
    |> password_changeset(attrs, Keyword.put_new(opts, :hash_password, true))
    |> confirm_changeset()
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Liminal.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  A user changeset for inviting users (admin-created, no password).

  Validates username, casts role, and confirms the account.
  The invited user sets their password later via a reset link.
  """
  def invite_changeset(user, attrs) do
    user
    |> username_changeset(attrs)
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, ~w(admin user))
    |> confirm_changeset()
  end

  @doc """
  A user changeset for changing user-controlled preferences.
  """
  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:auto_mark_viewed_on_open, :default_tags_enabled, :default_tag_id])
    |> maybe_clear_default_tag()
    |> validate_default_tag()
  end

  defp maybe_clear_default_tag(changeset) do
    if get_field(changeset, :default_tags_enabled) == false do
      put_change(changeset, :default_tag_id, nil)
    else
      changeset
    end
  end

  defp validate_default_tag(changeset) do
    if get_field(changeset, :default_tags_enabled) do
      changeset
      |> validate_required([:default_tag_id])
      |> validate_default_tag_ownership()
    else
      changeset
    end
  end

  defp validate_default_tag_ownership(changeset) do
    user_id = changeset.data.id
    tag_id = get_field(changeset, :default_tag_id)

    cond do
      is_nil(tag_id) or is_nil(user_id) ->
        changeset

      true ->
        case Liminal.Repo.get(Liminal.Links.Tag, tag_id) do
          %{user_id: ^user_id} ->
            changeset

          _ ->
            add_error(changeset, :default_tag_id, "must be one of your tags")
        end
    end
  end

  @doc """
  A user changeset for changing the role.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, ~w(admin user))
  end

  @doc """
  Returns a changeset that disables the user by setting `disabled_at`.
  """
  def disable_changeset(user), do: change(user, disabled_at: DateTime.utc_now(:second))

  @doc """
  Returns a changeset that enables the user by clearing `disabled_at`.
  """
  def enable_changeset(user), do: change(user, disabled_at: nil)
end
