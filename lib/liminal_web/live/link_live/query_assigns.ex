defmodule LiminalWeb.LinkLive.QueryAssigns do
  use LiminalWeb, :html

  alias Liminal.Links
  alias LiminalWeb.LinkLive.Streaming

  import Phoenix.LiveView, only: [stream: 4]

  def apply_search_query(socket, query) do
    socket |> assign(:search_query, query) |> refetch_links()
  end

  def search_submit(socket, query) when query in [nil, ""], do: socket
  def search_submit(socket, query), do: apply_search_query(socket, query)

  def refetch_links(socket) do
    scope = socket.assigns.current_scope

    socket = Streaming.cancel_all_viewed_removals(socket)

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
    |> stream(:links, links, reset: true)
  end

  def search_input_describedby(""), do: "link-search-hint"

  def search_input_describedby(_query), do: "link-search-hint link-search-status"

  def matches_filters?(link, assigns) do
    matches_viewed_filter?(link, assigns.filter) and
      matches_tag_filter?(link, assigns.filter_tag_ids) and
      matches_search_filter?(link, assigns.search_query)
  end

  def matches_viewed_filter?(_link, :all), do: true
  def matches_viewed_filter?(link, :unviewed), do: is_nil(link.viewed_at)
  def matches_viewed_filter?(link, :viewed), do: not is_nil(link.viewed_at)

  def leaving_unviewed_filter?(link, assigns) do
    assigns.filter == :unviewed and not is_nil(link.viewed_at) and
      matches_tag_filter?(link, assigns.filter_tag_ids) and
      matches_search_filter?(link, assigns.search_query)
  end

  def matches_tag_filter?(_link, []), do: true

  def matches_tag_filter?(link, tag_ids) do
    Enum.any?(link.link_tags, fn lt -> lt.tag_id in tag_ids end)
  end

  def matches_search_filter?(_link, query) when query in [nil, ""], do: true

  def matches_search_filter?(link, query) do
    Liminal.Links.TextSearch.matches?(link, query)
  end
end
