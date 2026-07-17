defmodule Liminal.Accounts.Credentials do
  @moduledoc """
  User credential operations: sudo-mode check, username/password/settings updates.
  """

  alias Liminal.Repo
  alias Liminal.Accounts.{Sessions, User}

  @doc """
  Returns `true` if the user authenticated within `minutes` minutes.

  The default window is 20 minutes (pass a negative value, e.g. `-20`).
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

  @doc "Updates the password and invalidates all existing session tokens."
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
end
