defmodule LiminalWeb.LinkLive.Index do
  use LiminalWeb, :live_view

  alias Liminal.Links
  alias LiminalWeb.LinkLive.Components
  alias LiminalWeb.LinkLive.Filters
  alias LiminalWeb.LinkLive.LinkActions
  alias LiminalWeb.LinkLive.LinkForms
  alias LiminalWeb.LinkLive.Shortcuts
  alias LiminalWeb.LinkLive.Streaming
  alias LiminalWeb.LinkLive.ViewedTransitions

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:links}>
      <Components.page_header
        shortcut_platform={@shortcut_platform}
        show_keyboard_shortcut_hints={@show_keyboard_shortcut_hints}
      />
      <Components.search_form
        search_query={@search_query}
        search_results_count={@search_results_count}
        shortcut_platform={@shortcut_platform}
        show_keyboard_shortcut_hints={@show_keyboard_shortcut_hints}
      />
      <Components.filters_and_sort filter={@filter} sort={@sort} />
      <Components.tag_filter_chips tags={@tags} filter_tag_ids={@filter_tag_ids} />

      <div id="link-shortcuts" phx-hook="LinkShortcuts" />

      <Components.masonry
        form={@form}
        tags={@tags}
        selected_tag_ids={@selected_tag_ids}
        shortcut_platform={@shortcut_platform}
        show_keyboard_shortcut_hints={@show_keyboard_shortcut_hints}
        show_clipboard_paste_button={@show_clipboard_paste_button}
        clipboard_has_link={@clipboard_has_link}
        streams={@streams}
        removing_link_ids={@removing_link_ids}
        auto_mark_viewed={@auto_mark_viewed}
        search_query={@search_query}
      />
      <Components.duplicate_modal
        duplicate_link={@duplicate_link}
        tags={@tags}
        pending_tag_ids={@pending_tag_ids}
      />
      <Components.edit_modal live_action={@live_action} edit_form={@edit_form} />
      <Components.tag_manager_modal
        live_action={@live_action}
        current_scope={@current_scope}
        tag_id={@tag_id}
      />
    </Layouts.app>
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
    {:noreply, stream_delete(socket, :links, %{id: link_id})}
  end

  def handle_info({:link_created, link}, socket) do
    {:noreply, Streaming.link_created(socket, link)}
  end

  def handle_info({LiminalWeb.TagLive.Index, :tags_changed}, socket) do
    tags = Links.list_tags(socket.assigns.current_scope)
    {:noreply, assign(socket, :tags, tags)}
  end

  def handle_info({:link_updated, link}, socket) do
    {:noreply, Streaming.link_updated(socket, link)}
  end

  def handle_info({:remove_viewed_link, link_id}, socket) do
    {:noreply, ViewedTransitions.start_viewed_removal(socket, link_id)}
  end

  def handle_info({:complete_viewed_removal, link_id}, socket) do
    {:noreply, ViewedTransitions.complete_viewed_removal(socket, link_id)}
  end

  @impl true
  def handle_event("validate", %{"link" => link_params}, socket) do
    {:noreply, LinkForms.validate_link(socket, link_params)}
  end

  def handle_event("validate_edit", %{"edit_link" => link_params}, socket) do
    {:noreply, LinkForms.validate_edit(socket, link_params)}
  end

  def handle_event("toggle_tag", %{"id" => tag_id}, socket) do
    {:noreply, Shortcuts.toggle_selected_tag(socket, tag_id)}
  end

  def handle_event("set_shortcut_platform", params, socket) do
    {:noreply, Shortcuts.set_shortcut_platform(socket, params)}
  end

  def handle_event("set_clipboard_has_link", params, socket) do
    {:noreply, Shortcuts.set_clipboard_has_link(socket, params)}
  end

  def handle_event("shortcut_focus_new_link", _params, socket) do
    {:noreply, Shortcuts.shortcut_focus_new_link(socket)}
  end

  def handle_event("focus_new_link", _params, socket) do
    {:noreply, Shortcuts.focus_new_link(socket)}
  end

  def handle_event("shortcut_paste_link", %{"url" => url}, socket) do
    {:noreply, Shortcuts.shortcut_paste_link(socket, url)}
  end

  def handle_event("shortcut_paste_no_link", _params, socket) do
    {:noreply, put_flash(socket, :error, "Clipboard does not contain a link")}
  end

  def handle_event("shortcut_toggle_tag_by_index", %{"index" => index}, socket) do
    case Shortcuts.index_to_tag(index, socket.assigns.tags) do
      nil -> {:noreply, socket}
      tag -> {:noreply, Shortcuts.toggle_selected_tag(socket, tag.id)}
    end
  end

  def handle_event("handle_shortcut_keydown", params, socket) do
    Shortcuts.handle_shortcut_keydown(socket, params)
  end

  def handle_event("save", %{"link" => link_params}, socket) do
    LinkForms.save_link(socket, socket.assigns.live_action, link_params)
  end

  def handle_event("confirm_duplicate_merge", _params, socket) do
    LinkForms.confirm_duplicate_merge(socket)
  end

  def handle_event("discard_duplicate", _params, socket) do
    {:noreply, LinkForms.clear_duplicate_state(socket)}
  end

  def handle_event("save_edit", %{"edit_link" => link_params}, socket) do
    LinkForms.save_edit(socket, link_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    LinkActions.delete_link(socket, id)
  end

  def handle_event("retry_indexing", %{"id" => id}, socket) do
    LinkActions.retry_indexing(socket, id)
  end

  def handle_event("open_link", %{"id" => id}, socket), do: LinkActions.open_link(socket, id)

  def handle_event("mark_viewed", %{"id" => id}, socket) do
    LinkActions.mark_viewed(socket, id)
  end

  def handle_event("mark_unviewed", %{"id" => id}, socket) do
    LinkActions.mark_unviewed(socket, id)
  end

  def handle_event("tag", %{"link-id" => link_id, "tag-id" => tag_id}, socket) do
    LinkActions.tag_link(socket, link_id, tag_id)
  end

  def handle_event("untag", %{"link-id" => link_id, "tag-id" => tag_id}, socket) do
    LinkActions.untag_link(socket, link_id, tag_id)
  end

  def handle_event("filter", %{"filter" => filter_str}, socket) do
    filter = String.to_existing_atom(filter_str)
    {:noreply, socket |> assign(:filter, filter) |> Streaming.refetch_links()}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, apply_search_query(socket, query)}
  end

  def handle_event("search_submit", %{"query" => query}, socket) when query in [nil, ""] do
    {:noreply, socket}
  end

  def handle_event("search_submit", %{"query" => query}, socket) do
    # iOS Safari clears `type="search"` inputs on Return before LiveView reads
    # the value. We use `type="text"` and ignore empty submit payloads so an
    # accidental submit does not wipe an active search.
    {:noreply, apply_search_query(socket, query)}
  end

  def handle_event("sort", %{"sort" => sort_str}, socket) do
    sort = String.to_existing_atom(sort_str)
    {:noreply, socket |> assign(:sort, sort) |> Streaming.refetch_links()}
  end

  def handle_event("toggle_filter_tag", %{"id" => tag_id}, socket) do
    updated = Filters.toggle_filter_tag_ids(socket.assigns.filter_tag_ids, tag_id)

    {:noreply,
     socket
     |> assign(:filter_tag_ids, updated)
     |> Streaming.refetch_links()}
  end

  defp apply_search_query(socket, query) do
    socket |> assign(:search_query, query) |> Streaming.refetch_links()
  end
end
