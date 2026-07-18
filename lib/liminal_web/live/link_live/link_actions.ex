defmodule LiminalWeb.LinkLive.LinkActions do
  alias Liminal.Links
  alias Phoenix.LiveView

  def delete_link(socket, id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)
    {:ok, _} = Links.delete_link(scope, link)

    {:noreply, LiveView.stream_delete(socket, :links, link)}
  end

  def retry_indexing(socket, id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)

    case Links.retry_indexing(scope, link) do
      {:ok, updated_link} ->
        {:noreply,
         socket
         |> LiveView.put_flash(:info, "Indexing retry queued")
         |> LiveView.stream_insert(:links, updated_link)}

      {:error, :reindex_busy} ->
        {:noreply,
         LiveView.put_flash(
           socket,
           :error,
           "A reindex job is already running. Try again when it finishes."
         )}
    end
  end

  def open_link(%{assigns: %{auto_mark_viewed: true}} = socket, id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)

    mark_opened_link_viewed(socket, scope, link)
  end

  def open_link(socket, _id), do: {:noreply, socket}

  def mark_viewed(socket, id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)
    {:ok, _} = Links.mark_viewed(scope, link)

    {:noreply, socket}
  end

  def mark_unviewed(socket, id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)
    {:ok, _} = Links.mark_unviewed(scope, link)
    updated_link = Links.get_link!(scope, id)

    {:noreply, LiveView.stream_insert(socket, :links, updated_link)}
  end

  def tag_link(socket, link_id, tag_id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, link_id)
    tag = Links.get_tag!(scope, tag_id)
    {:ok, _} = Links.tag_link(scope, link, tag)
    updated_link = Links.get_link!(scope, link_id)

    {:noreply, LiveView.stream_insert(socket, :links, updated_link)}
  end

  def untag_link(socket, link_id, tag_id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, link_id)
    tag = Links.get_tag!(scope, tag_id)

    case Links.cleanup_link(scope, link, tag) do
      {:ok, :link_deleted} ->
        {:noreply,
         socket
         |> LiveView.put_flash(:info, "Last tag removed — link deleted")
         |> LiveView.stream_delete(:links, link)}

      {:ok, :tag_removed} ->
        updated_link = Links.get_link!(scope, link_id)
        {:noreply, LiveView.stream_insert(socket, :links, updated_link)}
    end
  end

  defp mark_opened_link_viewed(socket, scope, %{viewed_at: nil} = link) do
    {:ok, _} = Links.mark_viewed(scope, link)
    {:noreply, socket}
  end

  defp mark_opened_link_viewed(socket, _scope, _link), do: {:noreply, socket}
end
