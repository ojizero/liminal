defmodule LiminalWeb.Admin.UserLive.Index do
  use LiminalWeb, :live_view

  import LiminalWeb.Admin.UserComponents

  alias Liminal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:admin}>
      <div id="admin-users-page" class="space-y-8">
        <div class="space-y-2">
          <.header>
            Admin
            <:subtitle>Manage instance access, roles, and account status.</:subtitle>
          </.header>
          <Layouts.admin_nav active={:users} />
        </div>

        <section id="user-management" aria-labelledby="user-management-heading" class="space-y-4">
          <.header id="user-management-heading" level={2}>
            Users
            <:subtitle>Invite people and manage their access to this instance.</:subtitle>
            <:actions>
              <.button variant="primary" patch={~p"/admin/users/new"}>
                <.icon name="hero-plus" class="size-4" /> Invite User
              </.button>
            </:actions>
          </.header>

          <.invite_panel live_action={@live_action} form={@form} />
          <.users_stream
            streams={@streams}
            current_user={@current_scope.user}
            reset_url={@reset_url}
            reset_user_id={@reset_user_id}
          />
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    users = Accounts.list_users(scope)

    socket =
      socket
      |> assign(:reset_url, nil)
      |> assign(:reset_user_id, nil)
      |> stream(:users, users)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Admin · Users")
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Accounts.change_invite_user()

    socket
    |> assign(:page_title, "Admin · Invite User")
    |> assign(:form, to_form(changeset, as: "user"))
    |> assign(:reset_url, nil)
    |> assign(:reset_user_id, nil)
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      user_params
      |> Accounts.change_invite_user()
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.invite_user(scope, user_params) do
      {:ok, {user, token}} ->
        reset_url = url(~p"/users/reset-password/#{token}")

        {:noreply,
         socket
         |> put_flash(
           :info,
           "User invited successfully. Share the link below so they can set their password."
         )
         |> assign(:reset_url, reset_url)
         |> assign(:reset_user_id, user.id)
         |> stream_insert(:users, user)
         |> push_patch(to: ~p"/admin/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
    end
  end

  def handle_event("make_admin", %{"id" => id}, socket) do
    update_user(socket, id, &Accounts.promote_user/2, &"#{&1.username} is now an admin.",
      error: &"Failed to make #{&1.username} an admin."
    )
  end

  def handle_event("step_down", _params, socket) do
    scope = socket.assigns.current_scope

    case Accounts.step_down_from_admin(scope) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{scope.user.username} is now a normal user.")
         |> redirect(to: ~p"/")}

      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "You are the last admin and cannot step down.")}

      {:error, :not_admin} ->
        {:noreply, put_flash(socket, :error, "You are not an admin.")}
    end
  end

  def handle_event("disable", %{"id" => id}, socket) do
    update_user(socket, id, &Accounts.disable_user/2, &"#{&1.username} disabled.",
      error: &"Failed to disable #{&1.username}."
    )
  end

  def handle_event("enable", %{"id" => id}, socket) do
    update_user(socket, id, &Accounts.enable_user/2, &"#{&1.username} enabled.",
      error: &"Failed to enable #{&1.username}."
    )
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)
    {:ok, _} = Accounts.delete_user(scope, user)

    {:noreply,
     socket
     |> put_flash(:info, "#{user.username} deleted.")
     |> stream_delete(:users, user)}
  end

  def handle_event("generate_reset_link", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)
    token = Accounts.generate_reset_password_token(scope, user)
    reset_url = url(~p"/users/reset-password/#{token}")

    {:noreply,
     socket
     |> assign(:reset_url, reset_url)
     |> assign(:reset_user_id, user.id)
     |> stream_insert(:users, user)}
  end

  def handle_event("dismiss_reset_link", _params, socket) do
    {:noreply,
     socket
     |> assign(:reset_url, nil)
     |> assign(:reset_user_id, nil)}
  end

  def handle_event("copied_to_clipboard", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied to clipboard")}
  end

  defp update_user(socket, id, update_fun, success_message_fun, opts) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)
    error_message_fun = Keyword.fetch!(opts, :error)

    case update_fun.(scope, user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, success_message_fun.(user))
         |> stream_insert(:users, updated_user)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, error_message_fun.(user))}
    end
  end
end
