defmodule LiminalWeb.LinkLive.Streaming do
  import Phoenix.Component, only: [assign: 3]

  alias Liminal.Links
  alias LiminalWeb.LinkLive.Filters
  alias LiminalWeb.LinkLive.ViewedTransitions
  alias Phoenix.LiveView

  def refetch_links(socket) do
    scope = socket.assigns.current_scope

    socket = ViewedTransitions.cancel_all_viewed_removals(socket)

    links =
      Links.list_links(scope,
        filter: socket.assigns.filter,
        sort: socket.assigns.sort,
        tag_ids: socket.assigns.filter_tag_ids,
        query: socket.assigns.search_query
      )

    socket
    |> assign(:search_results_count, length(links))
    |> assign(:removing_link_ids, MapSet.new())
    |> LiveView.stream(:links, links, reset: true)
  end

  def maybe_stream_insert_link(socket, link) do
    case {Filters.matches_filters?(link, socket.assigns), socket.assigns.sort} do
      {true, :time_added_desc} -> LiveView.stream_insert(socket, :links, link, at: 0)
      {true, _sort} -> refetch_links(socket)
      {false, _sort} -> socket
    end
  end

  def link_created(socket, link), do: maybe_stream_insert_link(socket, link)

  def link_updated(socket, link) do
    cond do
      Filters.matches_filters?(link, socket.assigns) ->
        socket
        |> ViewedTransitions.cancel_viewed_removal(link.id)
        |> clear_removing_link(link.id)
        |> insert_or_refetch(link)

      Filters.leaving_unviewed_filter?(link, socket.assigns) ->
        socket
        |> LiveView.stream_insert(:links, link)
        |> ViewedTransitions.schedule_viewed_removal(link.id)

      true ->
        LiveView.stream_delete(socket, :links, link)
    end
  end

  defp insert_or_refetch(socket, link) do
    case socket.assigns.sort do
      :time_added_desc -> LiveView.stream_insert(socket, :links, link)
      _sort -> refetch_links(socket)
    end
  end

  defp clear_removing_link(socket, link_id) do
    assign(socket, :removing_link_ids, MapSet.delete(socket.assigns.removing_link_ids, link_id))
  end
end
