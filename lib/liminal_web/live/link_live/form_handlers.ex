defmodule LiminalWeb.LinkLive.FormHandlers do
  use LiminalWeb, :html

  alias Liminal.Links
  alias LiminalWeb.LinkLive.{Streaming, TagHandlers}

  import Phoenix.LiveView,
    only: [put_flash: 3, push_event: 3, push_patch: 2, stream_delete: 3, stream_insert: 3]

  def validate(socket, link_params) do
    changeset =
      socket.assigns.link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    assign(socket, :form, to_form(changeset))
  end

  def validate_edit(socket, link_params) do
    changeset =
      socket.assigns.editing_link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    assign(socket, :edit_form, to_form(changeset, as: :edit_link))
  end

  def shortcut_focus_new_link(socket) do
    socket
    |> apply_default_tags()
    |> push_event("focus-new-link-url", %{scroll: true})
  end

  def shortcut_paste_link(socket, url) do
    changeset =
      socket.assigns.link
      |> Links.change_link(%{"url" => url})
      |> Map.put(:action, :validate)

    socket
    |> assign(:form, to_form(changeset))
    |> apply_default_tags()
    |> push_event("focus-new-link-url", %{scroll: true})
  end

  def save_link(socket, :index, link_params) do
    scope = socket.assigns.current_scope
    tag_ids = socket.assigns.selected_tag_ids

    changeset =
      socket.assigns.link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    cond do
      tag_ids == [] ->
        {:noreply, put_flash(socket, :error, "Select at least one tag")}

      not changeset.valid? ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      true ->
        url = Ecto.Changeset.get_field(changeset, :url)

        case Links.find_link_by_url(scope, url) do
          nil ->
            create_new_link(socket, link_params, tag_ids)

          existing ->
            existing = Links.get_link!(scope, existing.id)

            {:noreply,
             socket
             |> assign(:duplicate_link, existing)
             |> assign(:pending_link_params, link_params)
             |> assign(:pending_tag_ids, tag_ids)
             |> assign(:form, to_form(changeset))}
        end
    end
  end

  def confirm_duplicate_merge(socket) do
    scope = socket.assigns.current_scope
    link = socket.assigns.duplicate_link
    tag_ids = socket.assigns.pending_tag_ids

    case Links.merge_link_tags(scope, link, tag_ids) do
      {:ok, updated_link} ->
        new_link = %Liminal.Links.Link{}

        {:noreply,
         socket
         |> put_flash(:info, "Link updated")
         |> stream_insert(:links, updated_link)
         |> clear_duplicate_state()
         |> assign(:link, new_link)
         |> assign(:selected_tag_ids, [])
         |> assign(:form, to_form(Links.change_link(new_link)))}

      {:error, :invalid_tags} ->
        {:noreply, put_flash(socket, :error, "One or more selected tags are invalid")}

      {:error, :no_tags} ->
        {:noreply, put_flash(socket, :error, "Select at least one tag")}
    end
  end

  def discard_duplicate(socket), do: clear_duplicate_state(socket)

  def save_edit(socket, link_params) do
    scope = socket.assigns.current_scope

    case Links.update_link(scope, socket.assigns.editing_link, link_params) do
      {:ok, link} ->
        link = Links.get_link!(scope, link.id)

        {:noreply,
         socket
         |> put_flash(:info, "Link updated")
         |> stream_insert(:links, link)
         |> push_patch(to: ~p"/")}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: :edit_link))}
    end
  end

  def delete(socket, id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)
    {:ok, _} = Links.delete_link(scope, link)

    stream_delete(socket, :links, link)
  end

  def retry_indexing(socket, id) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)

    case Links.retry_indexing(scope, link) do
      {:ok, updated_link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Indexing retry queued")
         |> stream_insert(:links, updated_link)}

      {:error, :reindex_busy} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A reindex job is already running. Try again when it finishes."
         )}
    end
  end

  def open_link(%{assigns: %{auto_mark_viewed: false}} = socket, _id), do: {:noreply, socket}

  def open_link(socket, id) do
    scope = socket.assigns.current_scope

    socket
    |> maybe_mark_opened_link_viewed(scope, Links.get_link!(scope, id))
    |> then(&{:noreply, &1})
  end

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

    {:noreply, stream_insert(socket, :links, updated_link)}
  end

  def apply_default_tags(socket) do
    user = socket.assigns.current_scope.user

    with true <- user.default_tags_enabled,
         tag_id when not is_nil(tag_id) <- user.default_tag_id,
         tag_id <- TagHandlers.normalize_tag_id(tag_id),
         true <-
           Enum.any?(socket.assigns.tags, &(TagHandlers.normalize_tag_id(&1.id) == tag_id)) do
      assign(socket, :selected_tag_ids, [tag_id])
    else
      _ -> socket
    end
  end

  def create_new_link(socket, link_params, tag_ids) do
    scope = socket.assigns.current_scope

    case Links.create_link(scope, link_params, tag_ids) do
      {:ok, link} ->
        link = Links.get_link!(scope, link.id)
        new_link = %Liminal.Links.Link{}

        {:noreply,
         socket
         |> put_flash(:info, "Link added")
         |> Streaming.sync_link_to_stream({:maybe_insert, link})
         |> assign(:link, new_link)
         |> assign(:selected_tag_ids, [])
         |> assign(:form, to_form(Links.change_link(new_link)))}

      {:error, :no_tags} ->
        {:noreply, put_flash(socket, :error, "Select at least one tag")}

      {:error, :invalid_tags} ->
        {:noreply, put_flash(socket, :error, "One or more selected tags are invalid")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def clear_duplicate_state(socket) do
    socket
    |> assign(:duplicate_link, nil)
    |> assign(:pending_link_params, nil)
    |> assign(:pending_tag_ids, [])
  end

  def duplicate_pending_tags(tags, pending_tag_ids) do
    pending = MapSet.new(pending_tag_ids)
    Enum.filter(tags, fn tag -> tag.id in pending end)
  end

  defp maybe_mark_opened_link_viewed(socket, _scope, %{viewed_at: viewed_at})
       when not is_nil(viewed_at) do
    socket
  end

  defp maybe_mark_opened_link_viewed(socket, scope, link) do
    {:ok, _} = Links.mark_viewed(scope, link)
    socket
  end
end
