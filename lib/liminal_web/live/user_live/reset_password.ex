defmodule LiminalWeb.UserLive.ResetPassword do
  use LiminalWeb, :live_view

  alias Liminal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.narrow_page>
        <div class="text-center">
          <.header>
            Reset Password
            <:subtitle>Enter your new password below.</:subtitle>
          </.header>
        </div>

        <.form for={@form} id="reset-password-form" phx-change="validate" phx-submit="save">
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
            required
          />
          <.button variant="primary" class="w-full" phx-disable-with="Resetting…">
            Reset Password
          </.button>
        </.form>
      </Layouts.narrow_page>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Reset password link is invalid or has expired.")
         |> redirect(to: ~p"/users/log-in")}

      user ->
        changeset = Accounts.change_reset_password(user)

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:form, to_form(changeset, as: "user"))
         |> assign(:page_title, "Reset Password")}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_reset_password(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
    end
  end
end
