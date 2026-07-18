defmodule LiminalWeb.LinkLive.Filters do
  def matches_filters?(link, assigns) do
    matches_viewed_filter?(link, assigns.filter) and
      matches_tag_filter?(link, assigns.filter_tag_ids) and
      matches_search_filter?(link, assigns.search_query)
  end

  def matches_viewed_filter?(_link, :all), do: true
  def matches_viewed_filter?(link, :unviewed), do: is_nil(link.viewed_at)
  def matches_viewed_filter?(link, :viewed), do: not is_nil(link.viewed_at)

  def matches_search_filter?(_link, query) when query in [nil, ""], do: true

  def matches_search_filter?(link, query) do
    Liminal.Links.TextSearch.matches?(link, query)
  end

  def matches_tag_filter?(_link, []), do: true

  def matches_tag_filter?(link, tag_ids) do
    Enum.any?(link.link_tags, fn lt -> lt.tag_id in tag_ids end)
  end

  def search_input_describedby(""), do: "link-search-hint"

  def search_input_describedby(_query), do: "link-search-hint link-search-status"

  def toggle_filter_tag_ids(current, tag_id) do
    case tag_id in current do
      true -> List.delete(current, tag_id)
      false -> [tag_id | current]
    end
  end

  def leaving_unviewed_filter?(link, assigns) do
    assigns.filter == :unviewed and not is_nil(link.viewed_at) and
      matches_tag_filter?(link, assigns.filter_tag_ids) and
      matches_search_filter?(link, assigns.search_query)
  end
end
