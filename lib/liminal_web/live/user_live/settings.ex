defmodule LiminalWeb.UserLive.Settings do
  use LiminalWeb, :live_view

  import LiminalWeb.ExpiryPauseComponents
  import LiminalWeb.ReindexComponents, only: [reindex_scope_label: 2]
  import LiminalWeb.UserLive.SettingsComponents

  on_mount {LiminalWeb.UserAuth, :require_sudo_mode}

  alias Liminal.Accounts
  alias Liminal.Links
  alias LiminalWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:settings}>
      <div id="settings-page" class="space-y-8">
        <.header>
          Account Settings
          <:subtitle>Manage your account, preferences, and saved-link maintenance.</:subtitle>
        </.header>

        <.stats_section stats={@stats} />
        <.reindex_section reindex={@reindex} current_scope={@current_scope} />
        <.account_security_section
          username_form={@username_form}
          password_form={@password_form}
          trigger_submit={@trigger_submit}
          current_username={@current_username}
        />
        <.preferences_panel settings_form={@settings_form} tags={@tags} />
        <.expiry_pause_panel current_scope={@current_scope} pause_form={@pause_form} />
        <.account_actions_section current_scope={@current_scope} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    scope = socket.assigns.current_scope
    username_changeset = Accounts.change_user_username(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Liminal.PubSub, Links.Reindex.pubsub_topic())
      Links.subscribe_expiry_pause(scope)
    end

    socket =
      socket
      |> assign(:page_title, "Account Settings")
      |> assign(:stats, Links.user_stats(scope))
      |> assign(:reindex, Links.reindex_status())
      |> assign(:current_username, user.username)
      |> assign(:username_form, to_form(username_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:settings_form, to_form(Accounts.change_user_settings(user)))
      |> assign(:pause_form, pause_form(user))
      |> assign(:tags, Links.list_tags(scope))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_info({:reindex_progress, %{active: true} = reindex}, socket) do
    {:noreply, assign(socket, :reindex, reindex)}
  end

  def handle_info({:reindex_progress, reindex}, socket) do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(:reindex, reindex)
     |> assign(:stats, Links.user_stats(scope))}
  end

  def handle_info({:expiry_pause_changed, user}, socket) do
    {:noreply, apply_expiry_pause(socket, user)}
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

  def handle_event("pause_expiries", %{"expiry_pause" => params}, socket) do
    scope = socket.assigns.current_scope
    days = parse_days(params["days"])

    case change_expiry_pause(scope, params["enabled"], days) do
      :unchanged ->
        {:noreply, assign(socket, :pause_form, pause_form(scope.user, days))}

      {:ok, user} ->
        {:noreply,
         socket
         |> apply_expiry_pause(user, days)
         |> put_flash(:info, expiry_pause_flash(user))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update the expiry pause.")}
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

  def handle_event("start_reindex", %{"mode" => mode}, socket) do
    mode = String.to_existing_atom(mode)
    start_reindex(socket, mode)
  end

  def handle_event("cancel_reindex", _params, socket) do
    scope = socket.assigns.current_scope

    case Links.cancel_reindex(scope) do
      :ok ->
        {:noreply,
         socket
         |> assign(:reindex, Links.reindex_status())
         |> put_flash(:info, "Reindex job cancelled.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You cannot cancel this reindex job.")}
    end
  end

  defp change_expiry_pause(scope, "true", days), do: Links.pause_expiries(scope, days)

  # Picking a length while expiries are running just records the choice for later —
  # there is nothing to resume, so the panel should stay quiet.
  defp change_expiry_pause(scope, _enabled, _days) do
    if Links.expiry_paused?(scope), do: Links.resume_expiries(scope), else: :unchanged
  end

  defp apply_expiry_pause(socket, user, days \\ nil) do
    days = days || parse_days(socket.assigns.pause_form.params["days"])
    socket = UserAuth.assign_scope_user(socket, user)

    socket
    |> assign(:pause_form, pause_form(socket.assigns.current_scope.user, days))
    |> assign(:stats, Links.user_stats(socket.assigns.current_scope))
  end

  defp expiry_pause_flash(user) do
    case Links.expiry_pause_resumes_at(user) do
      nil -> "Expiries resumed."
      resumes_at -> "Expiries paused until #{Calendar.strftime(resumes_at, "%b %-d, %Y")}."
    end
  end

  defp start_reindex(socket, mode) do
    scope = socket.assigns.current_scope

    case Links.start_user_reindex(scope, mode) do
      {:ok, %{active: true} = reindex} ->
        {:noreply,
         socket
         |> assign(:reindex, reindex)
         |> put_flash(
           :info,
           "Reindex job started (#{reindex_scope_label(reindex.scope, reindex.mode)})."
         )}

      {:ok, reindex} ->
        {:noreply,
         socket
         |> assign(:reindex, reindex)
         |> put_flash(:info, "No links matched that reindex scope.")}

      {:error, :already_running} ->
        {:noreply,
         socket
         |> assign(:reindex, Links.reindex_status())
         |> put_flash(
           :error,
           "A reindex job is already running. Cancel it or wait for it to finish."
         )}
    end
  end
end
