defmodule Liminal.Accounts.ResetPasswords do
  @moduledoc """
  Admin-controlled password-reset token flows: generation, lookup, and reset.
  """

  alias Liminal.Repo
  alias Liminal.Accounts.{Admin, Sessions, User, UserToken}

  @doc """
  Generates a reset-password token for the given user. Requires admin scope.
  Cannot generate tokens for admins.

  Deletes any existing reset-password tokens for the user first.
  Returns the encoded token string.
  """
  def generate_reset_password_token(scope, user) do
    Admin.ensure_admin!(scope)
    Admin.ensure_not_admin!(user)

    Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
    {encoded_token, user_token} = UserToken.build_reset_password_token(user)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Returns the user for the given reset-password token, or `nil` when the token
  is invalid, expired, or the user is disabled.
  """
  def get_user_by_reset_password_token(encoded_token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(encoded_token) do
      Repo.one(query)
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user's password and invalidates all existing tokens.

  Returns `{:ok, {user, expired_tokens}}` or `{:error, changeset}`.
  """
  def reset_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Sessions.update_user_and_delete_all_tokens()
  end

  @doc "Returns a password changeset for the reset-password form."
  def change_reset_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end
end
