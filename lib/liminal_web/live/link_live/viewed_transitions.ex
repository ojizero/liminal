defmodule LiminalWeb.LinkLive.ViewedTransitions do
  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView

  @viewed_removal_delay_ms 1_000
  @viewed_removal_transition_ms 500

  def schedule_viewed_removal(socket, link_id) do
    socket = cancel_viewed_removal(socket, link_id)

    ref = Process.send_after(self(), {:remove_viewed_link, link_id}, @viewed_removal_delay_ms)

    assign(
      socket,
      :pending_viewed_removals,
      Map.put(socket.assigns.pending_viewed_removals, link_id, ref)
    )
  end

  def start_viewed_removal(socket, link_id) do
    socket = cancel_viewed_removal(socket, link_id)

    case {socket.assigns.filter, MapSet.member?(socket.assigns.removing_link_ids, link_id)} do
      {:unviewed, false} -> schedule_viewed_fade(socket, link_id)
      _ -> socket
    end
  end

  def complete_viewed_removal(socket, link_id) do
    socket
    |> cancel_viewed_removal(link_id)
    |> clear_removing_link(link_id)
    |> maybe_delete_from_unviewed(link_id)
  end

  def cancel_viewed_removal(socket, link_id) do
    case Map.fetch(socket.assigns.pending_viewed_removals, link_id) do
      {:ok, ref} ->
        Process.cancel_timer(ref)

        assign(
          socket,
          :pending_viewed_removals,
          Map.delete(socket.assigns.pending_viewed_removals, link_id)
        )

      :error ->
        socket
    end
  end

  def cancel_all_viewed_removals(socket) do
    for {_link_id, ref} <- socket.assigns.pending_viewed_removals do
      Process.cancel_timer(ref)
    end

    socket
    |> assign(:pending_viewed_removals, %{})
    |> assign(:removing_link_ids, MapSet.new())
  end

  defp schedule_viewed_fade(socket, link_id) do
    ref =
      Process.send_after(
        self(),
        {:complete_viewed_removal, link_id},
        @viewed_removal_transition_ms
      )

    socket
    |> assign(:removing_link_ids, MapSet.put(socket.assigns.removing_link_ids, link_id))
    |> assign(
      :pending_viewed_removals,
      Map.put(socket.assigns.pending_viewed_removals, link_id, ref)
    )
  end

  defp clear_removing_link(socket, link_id) do
    assign(socket, :removing_link_ids, MapSet.delete(socket.assigns.removing_link_ids, link_id))
  end

  defp maybe_delete_from_unviewed(%{assigns: %{filter: :unviewed}} = socket, link_id) do
    LiveView.stream_delete(socket, :links, %{id: link_id})
  end

  defp maybe_delete_from_unviewed(socket, _link_id), do: socket
end
