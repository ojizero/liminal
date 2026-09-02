defmodule LiminalWeb.ExpiryPauseHooks do
  @moduledoc """
  Answers the paused-expiries banner's resume button for every authenticated LiveView.

  The banner is part of the app layout, so the button can be pressed from any page.
  Rather than repeat the handler in each LiveView, this hook is attached once per
  `live_session` in the router.

  A LiveView that renders anything derived from the pause — the link cards do — should
  also subscribe with `Liminal.Links.subscribe_expiry_pause/1` and refresh on
  `{:expiry_pause_changed, user}`, which fires here and when a pause runs out on its own.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3]

  alias Liminal.Accounts.Scope
  alias Liminal.Accounts.User
  alias Liminal.Links
  alias LiminalWeb.UserAuth

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :expiry_pause_controls, :handle_event, &handle_event/3)}
  end

  defp handle_event(
         "resume_expiries",
         _params,
         %{assigns: %{current_scope: %Scope{user: %User{}} = scope}} = socket
       ) do
    case Links.resume_expiries(scope) do
      {:ok, user} ->
        {:halt,
         socket
         |> UserAuth.assign_scope_user(user)
         |> put_flash(:info, "Expiries resumed.")}

      {:error, _reason} ->
        {:halt, put_flash(socket, :error, "Could not resume expiries.")}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
