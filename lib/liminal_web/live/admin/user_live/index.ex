defmodule LiminalWeb.Admin.UserLive.Index do
  use LiminalWeb, :live_view

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

          <.panel :if={@live_action == :new} id="invite-user-panel" class="max-w-2xl space-y-4">
            <div>
              <h3 class="font-semibold">Invite a user</h3>
              <p class="text-sm text-base-content/60">
                Create an account and generate a secure password setup link.
              </p>
            </div>
            <.form
              for={@form}
              id="admin-invite-user-form"
              phx-change="validate"
              phx-submit="save"
            >
              <.input
                field={@form[:username]}
                type="text"
                label="Username"
                autocomplete="off"
                required
              />
              <.input
                field={@form[:role]}
                type="select"
                label="Role"
                options={[{"User", "user"}, {"Admin", "admin"}]}
              />
              <div class="mt-2 flex gap-2">
                <.button variant="primary" phx-disable-with="Inviting…">Invite User</.button>
                <.button patch={~p"/admin/users"}>Cancel</.button>
              </div>
            </.form>
          </.panel>

          <div id="users" phx-update="stream" class="space-y-3">
            <div
              id="users-empty"
              role="status"
              class="hidden only:block rounded-xl border border-dashed border-base-300 py-12 text-center text-base-content/50"
            >
              No users found.
            </div>
            <div
              :for={{id, user} <- @streams.users}
              id={id}
              class="group flex flex-col gap-3 rounded-xl border border-base-300 bg-base-200/70 p-5 shadow-sm"
            >
              <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                    <span class="font-medium">{user.username}</span>
                    <span class={[
                      "badge badge-sm",
                      if(user.role == "admin", do: "badge-primary", else: "badge-ghost")
                    ]}>
                      {user.role}
                    </span>
                    <%= if user.disabled_at do %>
                      <span class="badge badge-sm badge-error">disabled</span>
                    <% else %>
                      <span class="badge badge-sm badge-success">active</span>
                    <% end %>
                  </div>
                </div>

                <%= cond do %>
                  <% user.role == "admin" and user.id == @current_scope.user.id -> %>
                    <div class="flex flex-wrap items-center gap-1 transition-opacity sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100">
                      <.button
                        variant="ghost"
                        class="btn-sm"
                        phx-click="step_down"
                        data-confirm="Are you sure? You will need another admin to restore your privileges."
                      >
                        Become normal user
                      </.button>
                    </div>
                  <% user.role == "admin" -> %>
                    <%!-- Other admin users — no actions --%>
                  <% true -> %>
                    <div class="flex flex-wrap items-center gap-1 transition-opacity sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100">
                      <.button
                        variant="ghost"
                        class="btn-sm"
                        phx-click="make_admin"
                        phx-value-id={user.id}
                        data-confirm="Make this user an admin?"
                      >
                        Make admin
                      </.button>
                      <%= if user.disabled_at do %>
                        <.button
                          variant="ghost"
                          class="btn-sm"
                          phx-click="enable"
                          phx-value-id={user.id}
                        >
                          Enable
                        </.button>
                      <% else %>
                        <.button
                          variant="ghost"
                          class="btn-sm"
                          phx-click="disable"
                          phx-value-id={user.id}
                        >
                          Disable
                        </.button>
                      <% end %>
                      <.button
                        variant="ghost"
                        class="btn-sm"
                        phx-click="generate_reset_link"
                        phx-value-id={user.id}
                      >
                        Reset Password
                      </.button>
                      <.button
                        variant="ghost"
                        class="btn-sm hover:text-error"
                        phx-click="delete"
                        phx-value-id={user.id}
                        data-confirm="Are you sure you want to delete this user?"
                      >
                        Delete
                      </.button>
                    </div>
                <% end %>
              </div>

              <%= if @reset_url && @reset_user_id == user.id do %>
                <div class="flex w-full flex-col gap-2 border-t border-base-300 pt-3 sm:flex-row sm:items-center">
                  <label for={"reset-url-#{user.id}"} class="sr-only">
                    Password reset link for {user.username}
                  </label>
                  <input
                    type="text"
                    readonly
                    value={@reset_url}
                    id={"reset-url-#{user.id}"}
                    class="input input-sm input-bordered min-w-0 flex-1 font-mono text-xs"
                  />
                  <div class="flex shrink-0 gap-1">
                    <.button
                      id={"copy-reset-url-#{user.id}"}
                      variant="ghost"
                      class="btn-sm"
                      phx-hook="CopyToClipboard"
                      data-clipboard-text={@reset_url}
                      aria-label={"Copy password reset link for #{user.username}"}
                    >
                      Copy
                    </.button>
                    <.button variant="ghost" class="btn-sm" phx-click="dismiss_reset_link">
                      Dismiss
                    </.button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
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
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)

    case Accounts.promote_user(scope, user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{user.username} is now an admin.")
         |> stream_insert(:users, updated_user)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to make #{user.username} an admin.")}
    end
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
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)

    case Accounts.disable_user(scope, user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{user.username} disabled.")
         |> stream_insert(:users, updated_user)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disable #{user.username}.")}
    end
  end

  def handle_event("enable", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)

    case Accounts.enable_user(scope, user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{user.username} enabled.")
         |> stream_insert(:users, updated_user)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to enable #{user.username}.")}
    end
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
end
