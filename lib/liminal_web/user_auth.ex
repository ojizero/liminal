defmodule LiminalWeb.UserAuth do
  use LiminalWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Liminal.Accounts
  alias Liminal.Accounts.Scope

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_liminal_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies, when present, will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7

  @doc """
  Logs the user in.

  Redirects to the session's `:user_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    conn
    |> get_session(:live_socket_id)
    |> broadcast_live_socket_disconnect()

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  defp broadcast_live_socket_disconnect(nil), do: :ok

  defp broadcast_live_socket_disconnect(live_socket_id) do
    LiminalWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Reissues the session token once it is older than the configured age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  # Returns `{token, conn}` from the session or the remember-me cookie, else `nil`.
  defp ensure_user_token(conn) do
    case get_session(conn, :user_token) do
      nil ->
        conn
        |> fetch_cookies(signed: [@remember_me_cookie])
        |> ensure_user_token_from_cookie()

      token ->
        {token, conn}
    end
  end

  defp ensure_user_token_from_cookie(conn) do
    case conn.cookies[@remember_me_cookie] do
      nil ->
        nil

      token ->
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
    end
  end

  # Reissue the session token once it is older than the configured reissue age.
  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)
    reissue_expired_user_session_token(conn, user, token_age >= @session_reissue_age_in_days)
  end

  defp reissue_expired_user_session_token(conn, user, true) do
    create_or_extend_session(conn, user, %{})
  end

  defp reissue_expired_user_session_token(conn, _user, false), do: conn

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session when the user is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _user) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      LiminalWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_scope` - Assigns current_scope
      to socket assigns based on user_token, or nil when
      there's no user_token or no matching user.

    * `:require_authenticated` - Authenticates the user from the session,
      and assigns the current_scope to socket assigns based
      on user_token.
      Redirects to login page without a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_scope`:

      defmodule LiminalWeb.PageLive do
        use LiminalWeb, :live_view

        on_mount {LiminalWeb.UserAuth, :mount_current_scope}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{LiminalWeb.UserAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)
    require_authenticated_mount(socket)
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)
    require_sudo_mount(socket, Accounts.sudo_mode?(socket.assigns.current_scope.user, -10))
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = mount_current_scope(socket, session)
    require_admin_mount(socket)
  end

  defp require_sudo_mount(socket, true), do: {:cont, socket}

  defp require_sudo_mount(socket, false) do
    halt_with_redirect(
      socket,
      ~p"/users/log-in",
      "You must re-authenticate to access this page."
    )
  end

  defp require_authenticated_mount(
         %{
           assigns: %{current_scope: %Scope{user: %Accounts.User{}}}
         } = socket
       ) do
    {:cont, socket}
  end

  defp require_authenticated_mount(socket) do
    halt_with_redirect(
      socket,
      unauthenticated_redirect_path(),
      "You must log in to access this page."
    )
  end

  defp require_admin_mount(%{assigns: %{current_scope: %Scope{} = scope}} = socket) do
    authorize_admin_mount(socket, Scope.admin?(scope))
  end

  defp require_admin_mount(socket) do
    halt_with_redirect(socket, ~p"/", "You are not authorized to access this page.")
  end

  defp authorize_admin_mount(socket, true), do: {:cont, socket}

  defp authorize_admin_mount(socket, false) do
    halt_with_redirect(socket, ~p"/", "You are not authorized to access this page.")
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      session
      |> user_from_session()
      |> Scope.for_user()
    end)
  end

  defp user_from_session(%{"user_token" => user_token}) do
    case Accounts.get_user_by_session_token(user_token) do
      {user, _token_inserted_at} -> user
      nil -> nil
    end
  end

  defp user_from_session(_session), do: nil

  # Puts a flash error and redirects the socket, returning `{:halt, socket}`.
  defp halt_with_redirect(socket, path, message) do
    socket =
      socket
      |> Phoenix.LiveView.put_flash(:error, message)
      |> Phoenix.LiveView.redirect(to: path)

    {:halt, socket}
  end

  # Returns the redirect path for unauthenticated users:
  # login when admins exist, registration page on fresh install.
  defp unauthenticated_redirect_path do
    case Accounts.any_admins?() do
      true -> ~p"/users/log-in"
      false -> ~p"/users/register"
    end
  end

  @doc "Returns the path to redirect to after log in."
  # the user was already logged in, redirect to settings
  def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{user: %Accounts.User{}}}}) do
    ~p"/"
  end

  def signed_in_path(_), do: ~p"/"

  @doc """
  Plug for routes that require the user to be authenticated.
  """
  def require_authenticated_user(
        %{assigns: %{current_scope: %Scope{user: %Accounts.User{}}}} = conn,
        _opts
      ) do
    conn
  end

  def require_authenticated_user(conn, _opts) do
    conn
    |> put_flash(:error, "You must log in to access this page.")
    |> maybe_store_return_to()
    |> redirect(to: unauthenticated_redirect_path())
    |> halt()
  end

  @doc """
  Plug for routes that require the user to be an admin.
  """
  def require_admin_user(%{assigns: %{current_scope: %Scope{} = scope}} = conn, _opts) do
    authorize_admin_user(conn, Scope.admin?(scope))
  end

  def require_admin_user(conn, _opts), do: deny_admin_user(conn)

  defp authorize_admin_user(conn, true), do: conn

  defp authorize_admin_user(conn, false), do: deny_admin_user(conn)

  defp deny_admin_user(conn) do
    conn
    |> put_flash(:error, "You are not authorized to access this page.")
    |> redirect(to: ~p"/")
    |> halt()
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
