defmodule LiminalWeb.UserLive.SettingsHandlers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 1, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  use Phoenix.VerifiedRoutes,
    endpoint: LiminalWeb.Endpoint,
    router: LiminalWeb.Router,
    statics: LiminalWeb.static_paths()

  alias Liminal.Accounts
  alias Liminal.Links

  def refresh_stats_on_idle(socket, %{active: true}), do: socket

  def refresh_stats_on_idle(socket, _reindex) do
    scope = socket.assigns.current_scope
    assign(socket, :stats, Links.user_stats(scope))
  end

  def validate_username(socket, user_params) do
    username_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_username(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, username_form: username_form)}
  end

  def update_username(socket, user_params) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.update_user_username(user, user_params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:current_username, updated_user.username)
         |> assign(
           :username_form,
           to_form(Accounts.change_user_username(updated_user, %{}))
         )
         |> put_flash(:info, "Username updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :username_form, to_form(changeset, action: :insert))}
    end
  end

  def validate_password(socket, user_params) do
    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def update_password(socket, user_params) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply,
         assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def update_settings(socket, user_params) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_settings(user, user_params) do
      {:ok, updated_user} ->
        scope_user = %{
          user
          | auto_mark_viewed_on_open: updated_user.auto_mark_viewed_on_open,
            default_tags_enabled: updated_user.default_tags_enabled,
            default_tag_id: updated_user.default_tag_id
        }

        scope = %{socket.assigns.current_scope | user: scope_user}

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign(:settings_form, to_form(Accounts.change_user_settings(scope_user)))
         |> put_flash(:info, "Preferences updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :settings_form, to_form(changeset))}
    end
  end

  def delete_account(socket) do
    scope = socket.assigns.current_scope
    true = Accounts.sudo_mode?(scope.user)

    case Accounts.delete_own_account(scope) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your account has been deleted.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :last_admin} ->
        {:noreply,
         put_flash(socket, :error, "You are the last admin and cannot delete your account.")}
    end
  end

  def become_normal_user(socket) do
    scope = socket.assigns.current_scope
    true = Accounts.sudo_mode?(scope.user)

    case Accounts.step_down_from_admin(scope) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "You are now a normal user.")
         |> redirect(to: ~p"/users/settings")}

      {:error, :last_admin} ->
        {:noreply,
         put_flash(socket, :error, "You are the last admin and cannot step down.")}
    end
  end
end
