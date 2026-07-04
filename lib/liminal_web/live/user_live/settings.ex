defmodule LiminalWeb.UserLive.Settings do
  use LiminalWeb, :live_view

  on_mount {LiminalWeb.UserAuth, :require_sudo_mode}

  alias Liminal.Accounts
  alias Liminal.Links

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.narrow_page>
        <div class="text-center">
          <.header>
            Account Settings
            <:subtitle>Manage your account username and password settings</:subtitle>
          </.header>
        </div>

        <.form
          for={@username_form}
          id="username_form"
          phx-submit="update_username"
          phx-change="validate_username"
        >
          <.input
            field={@username_form[:username]}
            type="text"
            label="Username"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button variant="primary" phx-disable-with="Changing…">Change Username</.button>
        </.form>

        <div class="divider" />

        <.form
          for={@password_form}
          id="password_form"
          action={~p"/users/update-password"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <input
            name={@password_form[:username].name}
            type="hidden"
            id="hidden_user_username"
            spellcheck="false"
            value={@current_username}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
            spellcheck="false"
          />
          <.button variant="primary" phx-disable-with="Saving…">
            Save Password
          </.button>
        </.form>

        <div class="divider" />
        <.header level={2}>
          Preferences
          <:subtitle>Tweak how Liminal behaves for you.</:subtitle>
        </.header>

        <.form for={@settings_form} id="settings_form" phx-change="update_settings">
          <.input
            field={@settings_form[:auto_mark_viewed_on_open]}
            type="checkbox"
            label="Mark links as viewed when opened"
            class="toggle toggle-primary"
          />
          <p class="text-sm text-base-content/60 -mt-1">
            When enabled, opening a link automatically marks it as viewed.
          </p>

          <.input
            field={@settings_form[:default_tags_enabled]}
            type="checkbox"
            label="Preselect a default tag for new links"
            class="toggle toggle-primary mt-4"
          />
          <p class="text-sm text-base-content/60 -mt-1">
            When enabled, your chosen tag is selected automatically when you add a new link.
          </p>

          <div :if={default_tags_enabled?(@settings_form)} class="mt-3">
            <.input
              field={@settings_form[:default_tag_id]}
              type="select"
              label="Default tag"
              prompt="Choose a tag…"
              options={default_tag_options(@tags)}
              required
            />
          </div>
        </.form>

        <%= if @current_scope.user.role == "admin" do %>
          <div class="divider" />
          <.header level={2}>
            Admin Role
            <:subtitle>
              You are currently an admin. You can step down to become a normal user.
            </:subtitle>
          </.header>
          <.button
            id="become-normal-user-btn"
            variant="ghost"
            class="btn-sm hover:text-warning"
            phx-click="become_normal_user"
            data-confirm="Are you sure? You will need another admin to restore your privileges."
          >
            Become normal user
          </.button>
        <% end %>

        <div class="divider" />
        <.header level={2}>
          Danger Zone
          <:subtitle>Permanently delete your account and all associated data.</:subtitle>
        </.header>
        <.button
          id="delete-account-btn"
          variant="ghost"
          class="btn-sm hover:text-error"
          phx-click="delete_account"
          data-confirm="Are you absolutely sure? This will permanently delete your account and all your data."
        >
          Delete my account
        </.button>
      </Layouts.narrow_page>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    scope = socket.assigns.current_scope
    username_changeset = Accounts.change_user_username(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:page_title, "Account Settings")
      |> assign(:current_username, user.username)
      |> assign(:username_form, to_form(username_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:settings_form, to_form(Accounts.change_user_settings(user)))
      |> assign(:tags, Links.list_tags(scope))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_username", params, socket) do
    %{"user" => user_params} = params

    username_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_username(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, username_form: username_form)}
  end

  def handle_event("update_username", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.update_user_username(user, user_params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:current_username, updated_user.username)
         |> assign(:username_form, to_form(Accounts.change_user_username(updated_user, %{})))
         |> put_flash(:info, "Username updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :username_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("update_settings", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_settings(user, user_params) do
      {:ok, updated_user} ->
        # Preserve virtual fields (e.g. authenticated_at) carried on the scope user.
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

  def handle_event("delete_account", _params, socket) do
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

  def handle_event("become_normal_user", _params, socket) do
    scope = socket.assigns.current_scope
    true = Accounts.sudo_mode?(scope.user)

    case Accounts.step_down_from_admin(scope) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "You are now a normal user.")
         |> redirect(to: ~p"/users/settings")}

      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "You are the last admin and cannot step down.")}
    end
  end

  defp default_tags_enabled?(form) do
    Phoenix.HTML.Form.normalize_value("checkbox", form[:default_tags_enabled].value)
  end

  defp default_tag_options(tags) do
    Enum.map(tags, &{&1.name, &1.id})
  end
end
