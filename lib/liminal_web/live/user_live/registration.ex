defmodule LiminalWeb.UserLive.Registration do
  use LiminalWeb, :live_view

  alias Liminal.Accounts
  alias Liminal.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.narrow_page>
        <div class="text-center">
          <%= if @admin_setup do %>
            <.header>
              Set up your instance
              <:subtitle>
                Create the first admin account to get started.
              </:subtitle>
            </.header>
          <% else %>
            <.header>
              Register for an account
              <:subtitle>
                Already registered?
                <.link navigate={~p"/users/log-in"} class="link link-primary font-semibold">
                  Log in
                </.link>
                to your account now.
              </:subtitle>
            </.header>
          <% end %>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
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
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm Password"
            autocomplete="new-password"
            spellcheck="false"
            required
          />

          <%= if @admin_setup do %>
            <.button variant="primary" class="w-full" phx-disable-with="Creating admin account…">
              Create Admin Account
            </.button>
          <% else %>
            <.button variant="primary" class="w-full" phx-disable-with="Creating account…">
              Create an account
            </.button>
          <% end %>
        </.form>
      </Layouts.narrow_page>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: LiminalWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    signups_enabled = Accounts.signups_enabled?()
    has_admins = Accounts.any_admins?()

    cond do
      signups_enabled ->
        changeset = Accounts.change_user_registration(%User{})

        {:ok,
         socket
         |> assign(:page_title, "Register")
         |> assign(:admin_setup, false)
         |> assign_form(changeset), temporary_assigns: [form: nil]}

      not has_admins ->
        changeset = Accounts.change_user_registration(%User{})

        {:ok,
         socket
         |> assign(:page_title, "Set up your instance")
         |> assign(:admin_setup, true)
         |> assign_form(changeset), temporary_assigns: [form: nil]}

      true ->
        {:ok,
         socket
         |> put_flash(:error, "Public signups are disabled. Please contact an administrator.")
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    if socket.assigns.admin_setup do
      case Accounts.register_admin(user_params) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "Admin account created successfully! Please log in.")
           |> push_navigate(to: ~p"/users/log-in")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    else
      case Accounts.register_user(user_params) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "Account created successfully! Please log in.")
           |> push_navigate(to: ~p"/users/log-in")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
