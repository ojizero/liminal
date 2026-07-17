defmodule LiminalWeb.Admin.UserLive.Components do
  @moduledoc false

  use LiminalWeb, :html

  attr :form, Phoenix.HTML.Form, required: true

  def invite_panel(assigns) do
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

  attr :user, :map, required: true
  attr :current_scope, :map, required: true
  attr :reset_url, :string
  attr :reset_user_id, :string

  def user_row(assigns) do
    ~H"""
    <div class="group flex flex-col gap-3 rounded-xl border border-base-300 bg-base-200/70 p-5 shadow-sm">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span class="font-medium">{@user.username}</span>
            <span class={[
              "badge badge-sm",
              if(@user.role == "admin", do: "badge-primary", else: "badge-ghost")
            ]}>
              {@user.role}
            </span>
            <%= if @user.disabled_at do %>
              <span class="badge badge-sm badge-error">disabled</span>
            <% else %>
              <span class="badge badge-sm badge-success">active</span>
            <% end %>
          </div>
        </div>

        <.user_actions user={@user} current_scope={@current_scope} />
      </div>

      <.reset_link_panel
        :if={@reset_url && @reset_user_id == @user.id}
        user={@user}
        reset_url={@reset_url}
      />
    </div>
    """
  end

  attr :user, :map, required: true
  attr :current_scope, :map, required: true

  defp user_actions(%{user: user, current_scope: %{user: %{id: current_id}}} = assigns)
       when user.role == "admin" and user.id == current_id do
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

  defp user_actions(%{user: %{role: "admin"}} = assigns) do
    ~H"""
    <%!-- Other admin users — no actions --%>
    """
  end

  defp user_actions(assigns) do
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
      <%= if @user.disabled_at do %>
        <.button variant="ghost" class="btn-sm" phx-click="enable" phx-value-id={@user.id}>
          Enable
        </.button>
      <% else %>
        <.button variant="ghost" class="btn-sm" phx-click="disable" phx-value-id={@user.id}>
          Disable
        </.button>
      <% end %>
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
end
