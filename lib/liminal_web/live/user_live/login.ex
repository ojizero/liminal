defmodule LiminalWeb.UserLive.Login do
  use LiminalWeb, :live_view

  alias Liminal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.narrow_page>
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= cond do %>
                <% !!@current_scope -> %>
                  You need to reauthenticate to perform sensitive actions on your account.
                <% @show_signup_link -> %>
                  Don't have an account? <.link
                    navigate={~p"/users/register"}
                    class="link link-primary font-semibold"
                    phx-no-format
                  >Sign up</.link> for an account now.
                <% true -> %>
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={@form[:username]}
            type="text"
            label="Username"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button variant="primary" class="w-full" name={@form[:remember_me].name} value="true">
            Log in and stay logged in <span aria-hidden="true">→</span>
          </.button>
          <.button variant="soft" class="w-full mt-2">
            Log in only this time
          </.button>
        </.form>
      </Layouts.narrow_page>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    signups_enabled = Accounts.signups_enabled?()
    has_admins = Accounts.any_admins?()

    if not signups_enabled and not has_admins do
      {:ok, push_navigate(socket, to: ~p"/users/register")}
    else
      username =
        Phoenix.Flash.get(socket.assigns.flash, :username) ||
          get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:username)])

      form = to_form(%{"username" => username}, as: "user")
      show_signup_link = signups_enabled or not has_admins

      {:ok, assign(socket, form: form, trigger_submit: false, show_signup_link: show_signup_link)}
    end
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
