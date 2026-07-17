defmodule LiminalWeb.LinkLive.Index do
  use LiminalWeb, :live_view

  alias Liminal.Links

  alias LiminalWeb.LinkLive.{
    Components,
    FilterParams,
    FormHandlers,
    QueryAssigns,
    Shortcuts,
    Streaming,
    TagHandlers
  }

  @viewed_removal_transition_ms 500

  @impl true
  def render(assigns) do
    ~H"""
    <Components.index {assigns} />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    tags = Links.list_tags(scope)
    links = Links.list_links(scope, filter: :unviewed)

    if connected?(socket), do: Links.subscribe_links(scope)

    link = %Liminal.Links.Link{}

    socket =
      socket
      |> assign(:tags, tags)
      |> assign(:auto_mark_viewed, scope.user.auto_mark_viewed_on_open)
      |> assign(:filter, :unviewed)
      |> assign(:sort, :time_added_desc)
      |> assign(:filter_tag_ids, [])
      |> assign(:search_query, "")
      |> assign(:search_results_count, length(links))
      |> assign(:link, link)
      |> assign(:selected_tag_ids, [])
      |> assign(:form, to_form(Links.change_link(link)))
      |> assign(:editing_link, nil)
      |> assign(:edit_form, nil)
      |> assign(:tag_id, nil)
      |> assign(:shortcut_platform, nil)
      |> assign(:show_keyboard_shortcut_hints, false)
      |> assign(:show_clipboard_paste_button, false)
      |> assign(:clipboard_has_link, false)
      |> assign(:duplicate_link, nil)
      |> assign(:pending_link_params, nil)
      |> assign(:pending_tag_ids, [])
      |> assign(:pending_viewed_removals, %{})
      |> assign(:removing_link_ids, MapSet.new())
      |> stream(:links, links)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "My Links")
    |> assign(:editing_link, nil)
    |> assign(:edit_form, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    link = Links.get_link!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Link")
    |> assign(:editing_link, link)
    |> assign(:edit_form, to_form(Links.change_link(link), as: :edit_link))
  end

  defp apply_action(socket, :manage_tags, _params) do
    socket
    |> assign(:page_title, "Manage Tags")
    |> assign(:tag_id, nil)
  end

  defp apply_action(socket, :new_tag, _params) do
    socket
    |> assign(:page_title, "New Tag")
    |> assign(:tag_id, nil)
  end

  defp apply_action(socket, :edit_tag, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Tag")
    |> assign(:tag_id, id)
  end

  @impl true
  def handle_info({:link_deleted, link_id}, socket) do
    {:noreply, Streaming.delete_link(socket, link_id)}
  end

  def handle_info({:link_created, link}, socket) do
    {:noreply, Streaming.sync_link_to_stream(socket, {:created, link})}
  end

  def handle_info({LiminalWeb.TagLive.Index, :tags_changed}, socket) do
    tags = Links.list_tags(socket.assigns.current_scope)
    {:noreply, assign(socket, :tags, tags)}
  end

  def handle_info({:link_updated, link}, socket) do
    {:noreply, Streaming.sync_link_to_stream(socket, {:updated, link})}
  end

  def handle_info({:remove_viewed_link, link_id}, socket) do
    {:noreply, Streaming.begin_viewed_removal(socket, link_id, @viewed_removal_transition_ms)}
  end

  def handle_info({:complete_viewed_removal, link_id}, socket) do
    {:noreply, Streaming.complete_viewed_removal(socket, link_id)}
  end

  @impl true
  def handle_event("validate", %{"link" => link_params}, socket) do
    {:noreply, FormHandlers.validate(socket, link_params)}
  end

  def handle_event("validate_edit", %{"edit_link" => link_params}, socket) do
    {:noreply, FormHandlers.validate_edit(socket, link_params)}
  end

  def handle_event("toggle_tag", %{"id" => tag_id}, socket) do
    {:noreply, TagHandlers.toggle_selected_tag(socket, tag_id)}
  end

  def handle_event("set_shortcut_platform", params, socket) do
    {:noreply, Shortcuts.set_platform(socket, params)}
  end

  def handle_event("set_clipboard_has_link", params, socket) do
    {:noreply, Shortcuts.set_clipboard_has_link(socket, params)}
  end

  def handle_event("shortcut_focus_new_link", _params, socket) do
    {:noreply, FormHandlers.shortcut_focus_new_link(socket)}
  end

  def handle_event("focus_new_link", _params, socket) do
    {:noreply, FormHandlers.apply_default_tags(socket)}
  end

  def handle_event("shortcut_paste_link", %{"url" => url}, socket) do
    {:noreply, FormHandlers.shortcut_paste_link(socket, url)}
  end

  def handle_event("shortcut_paste_no_link", _params, socket) do
    {:noreply, put_flash(socket, :error, "Clipboard does not contain a link")}
  end

  def handle_event("shortcut_toggle_tag_by_index", %{"index" => index}, socket) do
    {:noreply, Shortcuts.toggle_tag_by_index(socket, index)}
  end

  def handle_event("handle_shortcut_keydown", params, socket) do
    Shortcuts.handle_keydown(socket, params)
  end

  def handle_event("save", %{"link" => link_params}, socket) do
    FormHandlers.save_link(socket, socket.assigns.live_action, link_params)
  end

  def handle_event("confirm_duplicate_merge", _params, socket) do
    FormHandlers.confirm_duplicate_merge(socket)
  end

  def handle_event("discard_duplicate", _params, socket) do
    {:noreply, FormHandlers.discard_duplicate(socket)}
  end

  def handle_event("save_edit", %{"edit_link" => link_params}, socket) do
    FormHandlers.save_edit(socket, link_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:noreply, FormHandlers.delete(socket, id)}
  end

  def handle_event("retry_indexing", %{"id" => id}, socket) do
    FormHandlers.retry_indexing(socket, id)
  end

  def handle_event("open_link", %{"id" => id}, socket) do
    FormHandlers.open_link(socket, id)
  end

  def handle_event("mark_viewed", %{"id" => id}, socket) do
    FormHandlers.mark_viewed(socket, id)
  end

  def handle_event("mark_unviewed", %{"id" => id}, socket) do
    FormHandlers.mark_unviewed(socket, id)
  end

  def handle_event("tag", %{"link-id" => link_id, "tag-id" => tag_id}, socket) do
    TagHandlers.tag_link(socket, link_id, tag_id)
  end

  def handle_event("untag", %{"link-id" => link_id, "tag-id" => tag_id}, socket) do
    TagHandlers.untag_link(socket, link_id, tag_id)
  end

  def handle_event("filter", %{"filter" => filter_str}, socket) do
    case FilterParams.parse_filter(filter_str) do
      {:ok, filter} ->
        {:noreply, socket |> assign(:filter, filter) |> QueryAssigns.refetch_links()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, QueryAssigns.apply_search_query(socket, query)}
  end

  def handle_event("search_submit", %{"query" => query}, socket) do
    {:noreply, QueryAssigns.search_submit(socket, query)}
  end

  def handle_event("sort", %{"sort" => sort_str}, socket) do
    case FilterParams.parse_sort(sort_str) do
      {:ok, sort} -> {:noreply, socket |> assign(:sort, sort) |> QueryAssigns.refetch_links()}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("toggle_filter_tag", %{"id" => tag_id}, socket) do
    {:noreply, TagHandlers.toggle_filter_tag(socket, tag_id)}
  end
end
