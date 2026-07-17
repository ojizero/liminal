defmodule LiminalWeb.Admin.UserLive.Handlers do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3, stream_insert: 3, stream_delete: 3]

  alias Liminal.Accounts

  def with_user(socket, id, callback) when is_function(callback, 3) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)
    callback.(socket, scope, user)
  end

  def stream_user_ok(socket, updated_user, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> stream_insert(:users, updated_user)}
  end

  def stream_user_error(socket, message) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def promote_user(socket, scope, user) do
    case Accounts.promote_user(scope, user) do
      {:ok, updated_user} ->
        stream_user_ok(socket, updated_user, "#{user.username} is now an admin.")

      {:error, _reason} ->
        stream_user_error(socket, "Failed to make #{user.username} an admin.")
    end
  end

  def disable_user(socket, scope, user) do
    case Accounts.disable_user(scope, user) do
      {:ok, updated_user} ->
        stream_user_ok(socket, updated_user, "#{user.username} disabled.")

      {:error, _reason} ->
        stream_user_error(socket, "Failed to disable #{user.username}.")
    end
  end

  def enable_user(socket, scope, user) do
    case Accounts.enable_user(scope, user) do
      {:ok, updated_user} ->
        stream_user_ok(socket, updated_user, "#{user.username} enabled.")

      {:error, _reason} ->
        stream_user_error(socket, "Failed to enable #{user.username}.")
    end
  end

  def delete_user(socket, scope, user) do
    {:ok, _} = Accounts.delete_user(scope, user)

    {:noreply,
     socket
     |> put_flash(:info, "#{user.username} deleted.")
     |> stream_delete(:users, user)}
  end
end
