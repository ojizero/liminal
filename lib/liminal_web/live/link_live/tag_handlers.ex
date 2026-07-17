defmodule LiminalWeb.LinkLive.TagHandlers do
  use LiminalWeb, :html

  alias Liminal.Links
  alias LiminalWeb.LinkLive.QueryAssigns

  import Phoenix.LiveView, only: [put_flash: 3, stream_delete: 3, stream_insert: 3]

  def normalize_tag_id(id), do: to_string(id)

  def toggle_selected_tag(socket, tag_id) do
    tag_id = normalize_tag_id(tag_id)
    selected = Enum.map(socket.assigns.selected_tag_ids, &normalize_tag_id/1)

    updated =
      if tag_id in selected do
        List.delete(selected, tag_id)
      else
        [tag_id | selected]
      end

    assign(socket, :selected_tag_ids, updated)
  end

  def toggle_filter_tag(socket, tag_id) do
    current = socket.assigns.filter_tag_ids
    updated = if tag_id in current, do: List.delete(current, tag_id), else: [tag_id | current]

    socket
    |> assign(:filter_tag_ids, updated)
    |> QueryAssigns.refetch_links()
  end

  def tag_link(socket, link_id, tag_id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, link_id)
    tag = Links.get_tag!(scope, tag_id)
    {:ok, _} = Links.tag_link(scope, link, tag)
    updated_link = Links.get_link!(scope, link_id)

    {:noreply, stream_insert(socket, :links, updated_link)}
  end

  def untag_link(socket, link_id, tag_id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, link_id)
    tag = Links.get_tag!(scope, tag_id)

    case Links.cleanup_link(scope, link, tag) do
      {:ok, :link_deleted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Last tag removed — link deleted")
         |> stream_delete(:links, link)}

      {:ok, :tag_removed} ->
        updated_link = Links.get_link!(scope, link_id)
        {:noreply, stream_insert(socket, :links, updated_link)}
    end
  end
end
