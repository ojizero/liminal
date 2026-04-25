defmodule LiminalWeb.Admin.UserLive.Index do
  use LiminalWeb, :live_view

  alias Liminal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Users
        <:actions>
          <.button variant="primary" patch={~p"/admin/users/new"}>
            <.icon name="hero-plus" class="size-4" /> Invite User
          </.button>
        </:actions>
      </.header>

      <%!-- Inline form for inviting a new user --%>
      <div :if={@live_action == :new} class="mb-6 p-4 bg-base-200 rounded-lg">
        <.form for={@form} id="admin-invite-user-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:username]} type="text" label="Username" autocomplete="off" required />
          <.input
            field={@form[:role]}
            type="select"
            label="Role"
            options={[{"User", "user"}, {"Admin", "admin"}]}
          />
          <div class="flex gap-2 mt-2">
            <.button variant="primary" phx-disable-with="Inviting...">Invite User</.button>
            <.button patch={~p"/admin/users"}>Cancel</.button>
          </div>
        </.form>
      </div>

      <%!-- Users stream --%>
      <div id="users" phx-update="stream" class="space-y-3">
        <div id="users-empty" class="hidden only:block text-center py-8 text-base-content/50">
          No users found.
        </div>
        <div
          :for={{id, user} <- @streams.users}
          id={id}
          class="p-4 bg-base-200 rounded-lg flex items-center justify-between group"
        >
          <div class="flex items-center gap-3">
            <div>
              <span class="font-medium">{user.username}</span>
              <span class={[
                "badge badge-sm ml-2",
                if(user.role == "admin", do: "badge-primary", else: "badge-ghost")
              ]}>
                {user.role}
              </span>
              <%= if user.disabled_at do %>
                <span class="badge badge-sm badge-error ml-1">disabled</span>
              <% else %>
                <span class="badge badge-sm badge-success ml-1">active</span>
              <% end %>
            </div>
          </div>

          <%!-- Actions --%>
          <%= cond do %>
            <% user.role == "admin" and user.id != @current_scope.user.id -> %>
              <div class="flex gap-1 items-center opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  phx-click="demote_admin"
                  phx-value-id={user.id}
                  data-confirm="Remove admin privileges from this user?"
                  class="btn btn-ghost btn-sm"
                >
                  Become normal user
                </button>
              </div>
            <% user.role != "admin" -> %>
              <div class="flex gap-1 items-center opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  phx-click="make_admin"
                  phx-value-id={user.id}
                  data-confirm="Make this user an admin?"
                  class="btn btn-ghost btn-sm"
                >
                  Make admin
                </button>
                <%= if user.disabled_at do %>
                  <button
                    phx-click="enable"
                    phx-value-id={user.id}
                    class="btn btn-ghost btn-sm"
                  >
                    Enable
                  </button>
                <% else %>
                  <button
                    phx-click="disable"
                    phx-value-id={user.id}
                    class="btn btn-ghost btn-sm"
                  >
                    Disable
                  </button>
                <% end %>
                <button
                  phx-click="generate_reset_link"
                  phx-value-id={user.id}
                  class="btn btn-ghost btn-sm"
                >
                  Reset Password
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={user.id}
                  data-confirm="Are you sure you want to delete this user?"
                  class="btn btn-ghost btn-sm hover:text-error"
                >
                  Delete
                </button>
              </div>
            <% true -> %>
              <%!-- Current admin user — no actions (use settings page) --%>
          <% end %>

          <%!-- Reset link display --%>
          <%= if @reset_url && @reset_user_id == user.id do %>
            <div class="flex items-center gap-2 mt-2 w-full">
              <input
                type="text"
                readonly
                value={@reset_url}
                id={"reset-url-#{user.id}"}
                class="input input-sm input-bordered flex-1 font-mono text-xs"
              />
              <button
                id={"copy-reset-url-#{user.id}"}
                phx-hook=".CopyToClipboard"
                data-clipboard-text={@reset_url}
                class="btn btn-ghost btn-sm"
              >
                Copy
              </button>
              <button
                phx-click="dismiss_reset_link"
                class="btn btn-ghost btn-sm"
              >
                Dismiss
              </button>
            </div>
          <% end %>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const text = this.el.dataset.clipboardText
              navigator.clipboard.writeText(text)
            })
          }
        }
      </script>
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
    |> assign(:page_title, "Users")
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Accounts.change_invite_user()

    socket
    |> assign(:page_title, "Invite User")
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
         |> put_flash(:info, "User is now an admin.")
         |> stream_insert(:users, updated_user)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to make user an admin.")}
    end
  end

  def handle_event("demote_admin", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)

    case Accounts.demote_user(scope, user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User is now a normal user.")
         |> stream_insert(:users, updated_user)}

      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "Cannot demote the last admin.")}

      {:error, :self_demotion} ->
        {:noreply, put_flash(socket, :error, "Cannot demote yourself from the admin panel.")}

      {:error, :not_admin} ->
        {:noreply, put_flash(socket, :error, "User is not an admin.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to demote user.")}
    end
  end

  def handle_event("disable", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)

    case Accounts.disable_user(scope, user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User disabled.")
         |> stream_insert(:users, updated_user)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disable user.")}
    end
  end

  def handle_event("enable", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)

    case Accounts.enable_user(scope, user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User enabled.")
         |> stream_insert(:users, updated_user)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to enable user.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)
    {:ok, _} = Accounts.delete_user(scope, user)

    {:noreply,
     socket
     |> put_flash(:info, "User deleted.")
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
end
