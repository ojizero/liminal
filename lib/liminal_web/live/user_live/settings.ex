defmodule LiminalWeb.UserLive.Settings do
  use LiminalWeb, :live_view

  import LiminalWeb.UserLive.SettingsComponents

  alias Liminal.Accounts
  alias Liminal.Links
  alias LiminalWeb.ReindexHandlers
  alias LiminalWeb.UserLive.SettingsHandlers

  on_mount {LiminalWeb.UserAuth, :require_sudo_mode}

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
        <.credentials_section
          username_form={@username_form}
          password_form={@password_form}
          current_username={@current_username}
          trigger_submit={@trigger_submit}
        />
        <.preferences_section settings_form={@settings_form} tags={@tags} />
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
      |> assign(:tags, Links.list_tags(scope))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_info({:reindex_progress, reindex}, socket) do
    socket =
      socket
      |> assign(:reindex, reindex)
      |> SettingsHandlers.refresh_stats_on_idle(reindex)

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_username", params, socket) do
    %{"user" => user_params} = params
    SettingsHandlers.validate_username(socket, user_params)
  end

  def handle_event("update_username", %{"user" => user_params}, socket) do
    SettingsHandlers.update_username(socket, user_params)
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params
    SettingsHandlers.validate_password(socket, user_params)
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    SettingsHandlers.update_password(socket, user_params)
  end

  def handle_event("update_settings", %{"user" => user_params}, socket) do
    SettingsHandlers.update_settings(socket, user_params)
  end

  def handle_event("delete_account", _params, socket) do
    SettingsHandlers.delete_account(socket)
  end

  def handle_event("become_normal_user", _params, socket) do
    SettingsHandlers.become_normal_user(socket)
  end

  def handle_event("start_reindex", %{"mode" => mode}, socket) do
    ReindexHandlers.handle_start_reindex(socket, &Links.start_user_reindex/2, mode)
  end

  def handle_event("cancel_reindex", _params, socket) do
    ReindexHandlers.handle_cancel_reindex(socket)
  end
end
