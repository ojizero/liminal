defmodule Liminal.Accounts.PasswordReset do
  @moduledoc """
  Reset-password token lookup and password update flows.
  """

  alias Liminal.Accounts.{Sessions, User, UserToken}
  alias Liminal.Repo

  @doc false
  def create_reset_password_token(user, opts \\ []) do
    if Keyword.get(opts, :replace_existing, false) do
      Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
    end

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
    |> Sessions.update_user_and_delete_all_tokens()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password via reset.
  """
  def change_reset_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end
end
