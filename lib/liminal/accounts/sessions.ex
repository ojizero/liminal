defmodule Liminal.Accounts.Sessions do
  @moduledoc """
  Session token lifecycle: creation, lookup, deletion, and token-invalidating updates.
  """

  import Ecto.Query, warn: false

  alias Liminal.Repo
  alias Liminal.Accounts.UserToken

  @doc "Creates and persists a session token for the given user."
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Returns `{user, token_inserted_at}` when the session token is valid, else `nil`.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Deletes a persisted session token."
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc """
  Applies the given changeset and, on success, deletes every token for the user.

  Returns `{:ok, {updated_user, expired_tokens}}` or `{:error, changeset}`.
  """
  def update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
