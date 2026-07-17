defmodule Liminal.Accounts.UserToken do
  use Liminal.Schema
  import Ecto.Query
  alias Liminal.Accounts.UserToken

  @rand_size 32

  @session_validity_in_days 14
  @reset_password_validity_in_days 1

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, Liminal.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Session tokens are stored in the database so individual sessions can be revoked
  and expired independently of the signed cookie.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  @doc "Builds the query used to validate and load a session token."
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        where: is_nil(user.disabled_at),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc "Returns a query for a user's tokens in the given contexts."
  def by_user_and_contexts_query(user, contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end

  @doc "Builds a reset-password token and encoded token pair."
  def build_reset_password_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    encoded = Base.url_encode64(token, padding: false)
    {encoded, %UserToken{token: token, context: "reset_password", user_id: user.id}}
  end

  @doc "Builds the query used to validate and load a reset-password token."
  def verify_reset_password_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, token} ->
        query =
          from t in by_token_and_context_query(token, "reset_password"),
            join: user in assoc(t, :user),
            where: t.inserted_at > ago(@reset_password_validity_in_days, "day"),
            where: is_nil(user.disabled_at),
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
