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
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix's default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any, along with the token's creation time.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        where: is_nil(user.disabled_at),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Returns a query that matches all tokens for the given user and contexts.
  """
  def by_user_and_contexts_query(user, contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end

  @doc """
  Builds a reset password token for the given user.

  Returns the encoded token and the token struct to be persisted.
  """
  def build_reset_password_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    encoded = Base.url_encode64(token, padding: false)
    {encoded, %UserToken{token: token, context: "reset_password", user_id: user.id}}
  end

  @doc """
  Checks if the reset password token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  The token is valid if it matches the value in the database and it has
  not expired (after @reset_password_validity_in_days), and the user is not disabled.
  """
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
