defmodule LiminalWeb.ReindexHandlers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import LiminalWeb.ReindexComponents, only: [reindex_scope_label: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Liminal.Links

  @already_running_message "A reindex job is already running. Cancel it or wait for it to finish."

  def handle_start_reindex(socket, start_fun, mode) when is_function(start_fun, 2) do
    scope = socket.assigns.current_scope
    mode = String.to_existing_atom(mode)

    case start_fun.(scope, mode) do
      {:ok, reindex} ->
        {:noreply,
         socket
         |> assign(:reindex, reindex)
         |> put_flash(:info, start_reindex_flash_message(reindex))}

      {:error, :already_running} ->
        {:noreply,
         socket
         |> assign(:reindex, Links.reindex_status())
         |> put_flash(:error, @already_running_message)}
    end
  end

  def handle_cancel_reindex(socket) do
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

  def start_reindex_flash_message(%{active: true, scope: scope, mode: mode}) do
    "Reindex job started (#{reindex_scope_label(scope, mode)})."
  end

  def start_reindex_flash_message(_reindex) do
    "No links matched that reindex scope."
  end
end
