defmodule LiminalWeb.UserLive.SettingsComponents do
  @moduledoc false

  use LiminalWeb, :html

  import LiminalWeb.ReindexComponents
  import LiminalWeb.StatsComponents

  attr :stats, :map, required: true

  def stats_section(assigns) do
    ~H"""
    <section id="user-stats" aria-labelledby="user-stats-heading" class="space-y-4">
      <.header id="user-stats-heading" level={2}>
        Your link stats
        <:subtitle>A snapshot of your saved links and how they are doing.</:subtitle>
      </.header>
      <.stats_grid stats={@stats} />
    </section>
    """
  end

  attr :reindex, :map, required: true
  attr :current_scope, :map, required: true

  def reindex_section(assigns) do
    ~H"""
    <.panel>
      <.reindex_panel
        id="user-reindex"
        reindex={@reindex}
        current_scope={@current_scope}
        heading="Reindex your links"
        description="Re-fetch metadata for your saved links. Only one reindex job can run at a time across the instance."
        failed_confirm="Reindex your links that failed indexing? This runs in the background."
        all_confirm="Reindex all of your saved links? Existing metadata will be cleared first."
      />
    </.panel>
    """
  end

  attr :username_form, Phoenix.HTML.Form, required: true
  attr :password_form, Phoenix.HTML.Form, required: true
  attr :trigger_submit, :boolean, required: true
  attr :current_username, :string, required: true

  def account_security_section(assigns) do
    ~H"""
    <section id="account-security" aria-labelledby="account-security-heading" class="space-y-4">
      <.header id="account-security-heading" level={2}>
        Account & security
        <:subtitle>Update the credentials you use to access Liminal.</:subtitle>
      </.header>

      <div class="grid gap-4 lg:grid-cols-2">
        <.username_panel username_form={@username_form} />
        <.password_panel
          password_form={@password_form}
          trigger_submit={@trigger_submit}
          current_username={@current_username}
        />
      </div>
    </section>
    """
  end

  attr :username_form, Phoenix.HTML.Form, required: true

  defp username_panel(assigns) do
    ~H"""
    <.panel id="username-settings" class="space-y-4">
      <div>
        <h3 class="font-semibold">Username</h3>
        <p class="text-sm text-base-content/60">Change how your account is identified.</p>
      </div>
      <.form
        for={@username_form}
        id="username_form"
        phx-submit="update_username"
        phx-change="validate_username"
        class="space-y-3"
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
    </.panel>
    """
  end

  attr :password_form, Phoenix.HTML.Form, required: true
  attr :trigger_submit, :boolean, required: true
  attr :current_username, :string, required: true

  defp password_panel(assigns) do
    ~H"""
    <.panel id="password-settings" class="space-y-4">
      <div>
        <h3 class="font-semibold">Password</h3>
        <p class="text-sm text-base-content/60">Choose a strong password for your account.</p>
      </div>
      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
        class="space-y-3"
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
    </.panel>
    """
  end

  attr :settings_form, Phoenix.HTML.Form, required: true
  attr :tags, :list, required: true

  def preferences_panel(assigns) do
    ~H"""
    <.panel id="preferences-settings" class="space-y-4">
      <.header level={2}>
        Preferences
        <:subtitle>Tweak how Liminal behaves for you.</:subtitle>
      </.header>

      <.form
        for={@settings_form}
        id="settings_form"
        phx-change="update_settings"
        class="max-w-2xl"
      >
        <.input
          field={@settings_form[:auto_mark_viewed_on_open]}
          type="checkbox"
          label="Mark links as viewed when opened"
          class="toggle toggle-primary"
        />
        <p class="-mt-1 text-sm text-base-content/60">
          When enabled, opening a link automatically marks it as viewed.
        </p>

        <.input
          field={@settings_form[:default_tags_enabled]}
          type="checkbox"
          label="Preselect a default tag for new links"
          class="toggle toggle-primary mt-4"
        />
        <p class="-mt-1 text-sm text-base-content/60">
          When enabled, your chosen tag is selected automatically when you add a new link.
        </p>

        <div :if={default_tags_enabled?(@settings_form)} class="mt-3 max-w-sm">
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
    </.panel>
    """
  end

  attr :current_scope, :map, required: true

  def account_actions_section(assigns) do
    ~H"""
    <section id="account-actions" aria-labelledby="account-actions-heading" class="space-y-4">
      <.header id="account-actions-heading" level={2}>
        Account actions
        <:subtitle>Review access and permanent account changes.</:subtitle>
      </.header>

      <div class="grid gap-4 md:grid-cols-2">
        <.admin_role_panel :if={@current_scope.user.role == "admin"} />
        <.danger_zone_panel admin?={@current_scope.user.role == "admin"} />
      </div>
    </section>
    """
  end

  defp admin_role_panel(assigns) do
    ~H"""
    <.panel id="admin-role-settings" class="space-y-4">
      <div>
        <h3 class="font-semibold">Admin role</h3>
        <p class="text-sm text-base-content/60">
          You are currently an admin. You can step down to become a normal user.
        </p>
      </div>
      <.button
        id="become-normal-user-btn"
        variant="ghost"
        class="btn-sm hover:text-warning"
        phx-click="become_normal_user"
        data-confirm="Are you sure? You will need another admin to restore your privileges."
      >
        Become normal user
      </.button>
    </.panel>
    """
  end

  attr :admin?, :boolean, required: true

  defp danger_zone_panel(assigns) do
    ~H"""
    <.panel
      id="danger-zone-settings"
      class={[
        "space-y-4 border-error/25 bg-error/5",
        !@admin? && "md:col-span-2"
      ]}
    >
      <div>
        <h3 class="font-semibold text-error">Danger zone</h3>
        <p class="text-sm text-base-content/60">
          Permanently delete your account and all associated data.
        </p>
      </div>
      <.button
        id="delete-account-btn"
        variant="ghost"
        class="btn-sm text-error hover:bg-error/10 hover:text-error"
        phx-click="delete_account"
        data-confirm="Are you absolutely sure? This will permanently delete your account and all your data."
      >
        Delete my account
      </.button>
    </.panel>
    """
  end

  defp default_tags_enabled?(form) do
    Phoenix.HTML.Form.normalize_value("checkbox", form[:default_tags_enabled].value)
  end

  defp default_tag_options(tags) do
    Enum.map(tags, &{&1.name, &1.id})
  end
end
