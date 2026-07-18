defmodule LiminalWeb.Admin.UserComponents do
  @moduledoc false

  use LiminalWeb, :html

  attr :live_action, :atom, required: true
  attr :form, Phoenix.HTML.Form, default: nil

  def invite_panel(%{live_action: :new} = assigns) do
    ~H"""
    <.panel id="invite-user-panel" class="space-y-4">
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
        class="grid gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_minmax(12rem,1fr)_auto] lg:items-end"
      >
        <.input
          field={@form[:username]}
          type="text"
          label="Username"
          autocomplete="off"
          fieldset_class="mb-0"
          required
        />
        <.input
          field={@form[:role]}
          type="select"
          label="Role"
          options={[{"User", "user"}, {"Admin", "admin"}]}
          fieldset_class="mb-0"
        />
        <div class="flex gap-2 sm:col-span-2 lg:col-span-1">
          <.button variant="primary" phx-disable-with="Inviting…">Invite User</.button>
          <.button patch={~p"/admin/users"}>Cancel</.button>
        </div>
      </.form>
    </.panel>
    """
  end

  def invite_panel(assigns) do
    ~H"""
    """
  end

  attr :streams, :map, required: true
  attr :current_user, :map, required: true
  attr :reset_url, :string, default: nil
  attr :reset_user_id, :integer, default: nil

  def users_stream(assigns) do
    ~H"""
    <div id="users" phx-update="stream" class="space-y-3">
      <div
        id="users-empty"
        role="status"
        class="hidden only:block rounded-xl border border-dashed border-base-300 py-12 text-center text-base-content/50"
      >
        No users found.
      </div>
      <.user_card
        :for={{id, user} <- @streams.users}
        id={id}
        user={user}
        current_user={@current_user}
        reset_url={@reset_url}
        reset_user_id={@reset_user_id}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :user, :map, required: true
  attr :current_user, :map, required: true
  attr :reset_url, :string, default: nil
  attr :reset_user_id, :integer, default: nil

  def user_card(assigns) do
    assigns =
      assign(assigns, :action_state, user_action_state(assigns.user, assigns.current_user))

    ~H"""
    <div
      id={@id}
      class="group flex flex-col gap-3 rounded-xl border border-base-300 bg-base-200/70 p-5 shadow-sm"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span class="font-medium">{@user.username}</span>
            <.role_badge role={@user.role} />
            <.status_badge disabled_at={@user.disabled_at} />
          </div>
        </div>

        <.user_actions state={@action_state} user={@user} />
      </div>

      <.reset_link_panel
        :if={@reset_url && @reset_user_id == @user.id}
        user={@user}
        reset_url={@reset_url}
      />
    </div>
    """
  end

  attr :role, :string, required: true

  def role_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      if(@role == "admin", do: "badge-primary", else: "badge-ghost")
    ]}>
      {@role}
    </span>
    """
  end

  attr :disabled_at, :any, default: nil

  def status_badge(%{disabled_at: nil} = assigns) do
    ~H"""
    <span class="badge badge-sm badge-success">active</span>
    """
  end

  def status_badge(assigns) do
    ~H"""
    <span class="badge badge-sm badge-error">disabled</span>
    """
  end

  attr :state, :atom, required: true
  attr :user, :map, required: true

  def user_actions(%{state: :current_admin} = assigns) do
    ~H"""
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
    """
  end

  def user_actions(%{state: :other_admin} = assigns) do
    ~H"""
    """
  end

  def user_actions(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1 transition-opacity sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100">
      <.button
        variant="ghost"
        class="btn-sm"
        phx-click="make_admin"
        phx-value-id={@user.id}
        data-confirm="Make this user an admin?"
      >
        Make admin
      </.button>
      <.status_action_button state={@state} user={@user} />
      <.button
        variant="ghost"
        class="btn-sm"
        phx-click="generate_reset_link"
        phx-value-id={@user.id}
      >
        Reset Password
      </.button>
      <.button
        variant="ghost"
        class="btn-sm hover:text-error"
        phx-click="delete"
        phx-value-id={@user.id}
        data-confirm="Are you sure you want to delete this user?"
      >
        Delete
      </.button>
    </div>
    """
  end

  attr :state, :atom, required: true
  attr :user, :map, required: true

  defp status_action_button(%{state: :disabled_user} = assigns) do
    ~H"""
    <.button
      variant="ghost"
      class="btn-sm"
      phx-click="enable"
      phx-value-id={@user.id}
    >
      Enable
    </.button>
    """
  end

  defp status_action_button(assigns) do
    ~H"""
    <.button
      variant="ghost"
      class="btn-sm"
      phx-click="disable"
      phx-value-id={@user.id}
    >
      Disable
    </.button>
    """
  end

  attr :user, :map, required: true
  attr :reset_url, :string, required: true

  def reset_link_panel(assigns) do
    ~H"""
    <div class="flex w-full flex-col gap-2 border-t border-base-300 pt-3 sm:flex-row sm:items-center">
      <label for={"reset-url-#{@user.id}"} class="sr-only">
        Password reset link for {@user.username}
      </label>
      <input
        type="text"
        readonly
        value={@reset_url}
        id={"reset-url-#{@user.id}"}
        class="input input-sm input-bordered min-w-0 flex-1 font-mono text-xs"
      />
      <div class="flex shrink-0 gap-1">
        <.button
          id={"copy-reset-url-#{@user.id}"}
          variant="ghost"
          class="btn-sm"
          phx-hook="CopyToClipboard"
          data-clipboard-text={@reset_url}
          aria-label={"Copy password reset link for #{@user.username}"}
        >
          Copy
        </.button>
        <.button variant="ghost" class="btn-sm" phx-click="dismiss_reset_link">
          Dismiss
        </.button>
      </div>
    </div>
    """
  end

  defp user_action_state(%{role: "admin", id: user_id}, %{id: current_user_id})
       when user_id == current_user_id,
       do: :current_admin

  defp user_action_state(%{role: "admin"}, _current_user), do: :other_admin
  defp user_action_state(%{disabled_at: nil}, _current_user), do: :active_user
  defp user_action_state(_user, _current_user), do: :disabled_user
end
