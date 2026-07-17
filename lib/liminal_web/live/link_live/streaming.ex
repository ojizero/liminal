defmodule LiminalWeb.LinkLive.Streaming do
  use LiminalWeb, :html

  alias LiminalWeb.LinkLive.QueryAssigns

  import Phoenix.LiveView, only: [stream_delete: 3, stream_insert: 3, stream_insert: 4]

  @viewed_removal_delay_ms 1_000

  def delete_link(socket, link_id) do
    stream_delete(socket, :links, %{id: link_id})
  end

  def sync_link_to_stream(socket, {:created, link}) do
    insert_or_refetch(socket, link, QueryAssigns.matches_filters?(link, socket.assigns))
  end

  def sync_link_to_stream(socket, {:maybe_insert, link}) do
    insert_or_refetch(socket, link, QueryAssigns.matches_filters?(link, socket.assigns))
  end

  def sync_link_to_stream(socket, {:updated, link}) do
    sync_updated_link(
      socket,
      link,
      QueryAssigns.matches_filters?(link, socket.assigns),
      QueryAssigns.leaving_unviewed_filter?(link, socket.assigns)
    )
  end

  def insert_or_refetch(socket, link, true), do: insert_or_refetch(socket, link)
  def insert_or_refetch(socket, _link, false), do: socket

  def insert_or_refetch(%{assigns: %{sort: :time_added_desc}} = socket, link) do
    stream_insert(socket, :links, link, at: 0)
  end

  def insert_or_refetch(socket, _link), do: QueryAssigns.refetch_links(socket)

  def schedule_viewed_removal(socket, link_id) do
    socket = cancel_viewed_removal(socket, link_id)

    ref = Process.send_after(self(), {:remove_viewed_link, link_id}, @viewed_removal_delay_ms)

    assign(
      socket,
      :pending_viewed_removals,
      Map.put(socket.assigns.pending_viewed_removals, link_id, ref)
    )
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

  def begin_viewed_removal(%{assigns: %{filter: :unviewed}} = socket, link_id, transition_ms) do
    socket = cancel_viewed_removal(socket, link_id)
    maybe_stage_viewed_removal(socket, link_id, transition_ms)
  end

  def begin_viewed_removal(socket, link_id, _transition_ms) do
    cancel_viewed_removal(socket, link_id)
  end

  def complete_viewed_removal(%{assigns: %{filter: :unviewed}} = socket, link_id) do
    socket
    |> cancel_viewed_removal(link_id)
    |> assign(:removing_link_ids, MapSet.delete(socket.assigns.removing_link_ids, link_id))
    |> stream_delete(:links, %{id: link_id})
  end

  def complete_viewed_removal(socket, link_id) do
    socket
    |> cancel_viewed_removal(link_id)
    |> assign(:removing_link_ids, MapSet.delete(socket.assigns.removing_link_ids, link_id))
  end

  defp sync_updated_link(socket, link, true, _leaving_unviewed_filter?) do
    socket
    |> cancel_viewed_removal(link.id)
    |> assign(:removing_link_ids, MapSet.delete(socket.assigns.removing_link_ids, link.id))
    |> update_or_refetch(link)
  end

  defp sync_updated_link(socket, link, false, true) do
    socket
    |> stream_insert(:links, link)
    |> schedule_viewed_removal(link.id)
  end

  defp sync_updated_link(socket, link, false, false) do
    stream_delete(socket, :links, link)
  end

  defp maybe_stage_viewed_removal(socket, link_id, transition_ms) do
    if MapSet.member?(socket.assigns.removing_link_ids, link_id) do
      socket
    else
      ref = Process.send_after(self(), {:complete_viewed_removal, link_id}, transition_ms)

      socket
      |> assign(:removing_link_ids, MapSet.put(socket.assigns.removing_link_ids, link_id))
      |> assign(
        :pending_viewed_removals,
        Map.put(socket.assigns.pending_viewed_removals, link_id, ref)
      )
    end
  end

  defp update_or_refetch(%{assigns: %{sort: :time_added_desc}} = socket, link) do
    stream_insert(socket, :links, link)
  end

  defp update_or_refetch(socket, _link), do: QueryAssigns.refetch_links(socket)
end
