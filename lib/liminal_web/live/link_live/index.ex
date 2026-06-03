defmodule LiminalWeb.LinkLive.Index do
  use LiminalWeb, :live_view

  alias Liminal.Links

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:links}>
      <.header>
        My Links
        <:actions>
          <.button patch={~p"/tags"} variant="surface">Manage Tags</.button>
        </:actions>
      </.header>

      <%!-- Filter buttons and sort control --%>
      <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-2">
        <div class="flex flex-wrap gap-2">
          <button
            :for={filter <- [:unviewed, :all, :viewed]}
            phx-click="filter"
            phx-value-filter={filter}
            class={[
              "btn btn-sm",
              if(@filter == filter, do: "btn-primary", else: "btn-ghost")
            ]}
          >
            {filter |> Atom.to_string() |> String.capitalize()}
          </button>
        </div>

        <div class="flex items-center gap-2 sm:ml-auto">
          <span class="text-sm text-base-content/60 shrink-0">Sort:</span>
          <form phx-change="sort" id="sort-form" class="min-w-0 flex-1 sm:flex-none">
            <select
              name="sort"
              class="select select-sm select-bordered w-full min-w-0 sm:w-auto"
            >
              <option value="time_added_desc" selected={@sort == :time_added_desc}>
                Newest first
              </option>
              <option value="time_added_asc" selected={@sort == :time_added_asc}>Oldest first</option>
              <option value="expiring_soon" selected={@sort == :expiring_soon}>Expiring soon</option>
            </select>
          </form>
        </div>
      </div>

      <%!-- Tag filter chips --%>
      <div :if={@tags != []} class="flex flex-wrap gap-2 mb-4">
        <span class="text-sm text-base-content/60 self-center mr-1">Tags:</span>
        <button
          :for={tag <- @tags}
          phx-click="toggle_filter_tag"
          phx-value-id={tag.id}
          class={[
            "badge cursor-pointer select-none transition-colors",
            if(tag.id in @filter_tag_ids, do: "badge-primary", else: "badge-outline badge-ghost")
          ]}
        >
          {tag.name}
        </button>
      </div>

      <div id="link-shortcuts" phx-hook="LinkShortcuts" />

      <%!-- Links (masonry) --%>
      <div
        id="masonry"
        phx-hook="Masonry"
        class="relative"
      >
        <%!-- New link card (always first in masonry) --%>
        <div
          id="new-link-card"
          data-masonry-item
          class="card bg-base-200 border border-dashed border-base-content/20"
        >
          <div class="card-body p-4">
            <.form for={@form} id="link-form" phx-change="validate" phx-submit="save">
              <div class="fieldset mb-2">
                <.input
                  field={@form[:url]}
                  type="url"
                  placeholder="https://…"
                  phx-debounce="300"
                  fieldset_class="mb-0"
                  class={@shortcut_platform && @show_keyboard_shortcut_hints && "pr-20"}
                >
                  <:suffix :if={@shortcut_platform && @show_keyboard_shortcut_hints}>
                    <div
                      id="link-url-focus-shortcut"
                      class="pointer-events-none absolute inset-y-0 right-2 flex items-center gap-0.5"
                    >
                      <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                        {shortcut_mod_label(@shortcut_platform)}
                      </kbd>
                      <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                        K
                      </kbd>
                    </div>
                  </:suffix>
                </.input>
                <div
                  :if={@shortcut_platform && @show_keyboard_shortcut_hints}
                  class="mt-1 flex justify-end"
                >
                  <.with_tooltip
                    id="link-url-paste-shortcut"
                    tip="Paste a copied URL from your clipboard into the link field. This action works anywhere as long as you're not focusing an input field."
                    class="cursor-default inline-flex items-center gap-1.5"
                  >
                    <span class="text-xs text-base-content/45">Paste from anywhere</span>
                    <span class="inline-flex items-center gap-0.5">
                      <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                        {shortcut_mod_label(@shortcut_platform)}
                      </kbd>
                      <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                        V
                      </kbd>
                    </span>
                  </.with_tooltip>
                </div>
              </div>

              <div class="fieldset mt-3">
                <.input
                  field={@form[:note]}
                  type="textarea"
                  label="Note (optional)"
                  placeholder="Add a short note…"
                  rows="2"
                  maxlength="500"
                  phx-debounce="300"
                />
              </div>

              <div :if={@tags != []} class="mt-3">
                <div class="flex flex-wrap items-center gap-1.5">
                  <span class="text-sm font-medium">Tags</span>
                  <span
                    :if={@shortcut_platform && @show_keyboard_shortcut_hints}
                    class="flex items-center gap-0.5"
                  >
                    <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                      {shortcut_mod_label(@shortcut_platform)}
                    </kbd>
                    <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                      {shortcut_shift_label(@shortcut_platform)}
                    </kbd>
                    <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                      1..9
                    </kbd>
                  </span>
                </div>
                <div class="flex flex-wrap gap-2 mt-1">
                  <.with_tooltip
                    :for={{tag, idx} <- Enum.with_index(@tags, 1)}
                    tip={"Expires in #{tag.expires_in_days} days"}
                  >
                    <button
                      type="button"
                      phx-click="toggle_tag"
                      phx-value-id={tag.id}
                      id={"new-link-tag-#{idx}"}
                      data-shortcut-index={idx}
                      class={[
                        "badge badge-sm cursor-pointer select-none transition-colors",
                        if(tag.id in @selected_tag_ids,
                          do: "badge-primary",
                          else: "badge-outline badge-ghost"
                        )
                      ]}
                    >
                      {tag.name}
                    </button>
                  </.with_tooltip>
                </div>
              </div>

              <div class="flex justify-end mt-3">
                <.button variant="primary" phx-disable-with="Saving…">
                  <.icon name="hero-plus" class="size-4" /> Save
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <div id="links" phx-update="stream" class="contents">
          <div id="links-empty" class="hidden only:block text-center py-8 text-base-content/50">
            No links yet. Add one above!
          </div>
          <div
            :for={{id, link} <- @streams.links}
            id={id}
            data-masonry-item
            class={[
              "card bg-base-200",
              link.viewed_at && "opacity-60"
            ]}
          >
            <a
              :if={link.image_path}
              href={link.url}
              target="_blank"
              rel="noopener noreferrer"
              phx-click={@auto_mark_viewed && "open_link"}
              phx-value-id={link.id}
              class="h-56 w-full shrink-0 overflow-hidden block"
            >
              <img
                src={"/#{link.image_path}"}
                alt=""
                class="h-full w-full object-cover"
                loading="lazy"
              />
            </a>

            <div class="card-body p-4 gap-2">
              <a
                href={link.url}
                target="_blank"
                rel="noopener noreferrer"
                phx-click={@auto_mark_viewed && "open_link"}
                phx-value-id={link.id}
                class="font-bold line-clamp-2 hover:underline"
              >
                {link.title || link.url}
              </a>

              <%= case index_status(link) do %>
                <% :pending -> %>
                  <span class="badge badge-sm badge-ghost gap-1 w-fit">
                    <.icon name="hero-arrow-path" class="size-3 animate-spin" /> Fetching metadata…
                  </span>
                <% :scheduled -> %>
                  <.with_tooltip tip={"Next attempt #{format_datetime(link.index_next_attempt_at)}"}>
                    <span class="badge badge-sm badge-ghost w-fit">
                      Retry scheduled · {time_until(link.index_next_attempt_at)}
                    </span>
                  </.with_tooltip>
                <% :gave_up -> %>
                  <div class="flex flex-wrap items-center gap-2">
                    <.with_tooltip tip={"Gave up #{format_datetime(link.index_gave_up_at)} after #{link.index_attempt_count} attempts"}>
                      <span class="badge badge-sm badge-warning w-fit">
                        Indexing failed
                      </span>
                    </.with_tooltip>
                    <button
                      phx-click="retry_indexing"
                      phx-value-id={link.id}
                      class="btn btn-xs btn-outline"
                      phx-disable-with="Retrying…"
                    >
                      Retry indexing
                    </button>
                  </div>
                <% :indexed -> %>
              <% end %>

              <p :if={link.description} class="text-sm text-base-content/70 line-clamp-3">
                {link.description}
              </p>

              <div class="flex flex-wrap gap-1.5 mt-1">
                <.with_tooltip :for={lt <- link.link_tags} tip={time_remaining(lt.expires_at)}>
                  <span class="badge badge-sm badge-outline gap-1">
                    {lt.tag.name}
                    <.with_tooltip tip={"Remove #{lt.tag.name}"}>
                      <button
                        phx-click="untag"
                        phx-value-link-id={link.id}
                        phx-value-tag-id={lt.tag_id}
                        class="hover:text-error"
                      >
                        <.icon name="hero-x-mark" class="size-3" />
                      </button>
                    </.with_tooltip>
                  </span>
                </.with_tooltip>

                <% assigned_ids = Enum.map(link.link_tags, & &1.tag_id) %>
                <% available = Enum.reject(@tags, fn t -> t.id in assigned_ids end) %>
                <details :if={available != []} class="dropdown">
                  <summary class="badge badge-sm badge-ghost cursor-pointer gap-1">
                    <.icon name="hero-plus" class="size-3" /> tag
                  </summary>
                  <ul class="dropdown-content menu bg-base-200 rounded-box z-10 p-2 shadow mt-1">
                    <li :for={tag <- available}>
                      <.with_tooltip tip={"Expires in #{tag.expires_in_days} days"}>
                        <button phx-click="tag" phx-value-link-id={link.id} phx-value-tag-id={tag.id}>
                          {tag.name}
                        </button>
                      </.with_tooltip>
                    </li>
                  </ul>
                </details>
              </div>

              <blockquote
                :if={link.note && link.note != ""}
                class="border-l-3 border-info/60 pl-2.5 text-xs text-base-content/50 italic"
              >
                {link.note}
              </blockquote>

              <div class="flex items-center gap-2 mt-auto pt-2 border-t border-base-300 text-xs text-base-content/50">
                <%= if link.favicon_url do %>
                  <img src={link.favicon_url} class="size-4 rounded" alt="" />
                <% end %>
                <a
                  href={link.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  phx-click={@auto_mark_viewed && "open_link"}
                  phx-value-id={link.id}
                  class="truncate hover:underline hover:text-primary"
                >
                  {URI.parse(link.url).host || link.url}
                </a>

                <%= if expiry = Links.link_expires_at(link) do %>
                  <.with_tooltip tip={format_datetime(expiry)}>
                    <span
                      id={"link-expiry-#{link.id}"}
                      class="flex items-center gap-1 shrink-0 text-base-content/45"
                    >
                      <.icon name="hero-clock" class="size-3.5" />
                      {time_remaining(expiry)}
                    </span>
                  </.with_tooltip>
                <% end %>

                <div class="flex gap-1 ml-auto shrink-0">
                  <.with_tooltip tip={if(link.viewed_at, do: "Mark unviewed", else: "Mark viewed")}>
                    <button
                      phx-click={if(link.viewed_at, do: "mark_unviewed", else: "mark_viewed")}
                      phx-value-id={link.id}
                      class="btn btn-ghost btn-xs btn-circle"
                    >
                      <.icon
                        name={if(link.viewed_at, do: "hero-eye-slash", else: "hero-eye")}
                        class="size-3.5"
                      />
                    </button>
                  </.with_tooltip>
                  <.with_tooltip tip="Edit">
                    <.link patch={~p"/links/#{link.id}/edit"} class="btn btn-ghost btn-xs btn-circle">
                      <.icon name="hero-pencil-square" class="size-3.5" />
                    </.link>
                  </.with_tooltip>
                  <.with_tooltip tip="Delete">
                    <button
                      phx-click="delete"
                      phx-value-id={link.id}
                      data-confirm="Are you sure?"
                      class="btn btn-ghost btn-xs btn-circle hover:text-error"
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  </.with_tooltip>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.modal
        id="duplicate-link-modal"
        show={@duplicate_link != nil}
        on_cancel={JS.push("discard_duplicate")}
        closeable={true}
        show_close={false}
        box_class="sm:max-w-lg"
      >
        <:title>Link already exists</:title>
        <p class="text-sm text-base-content/70">
          {@duplicate_link && @duplicate_link.url} is already in your links.
        </p>

        <div class="space-y-3 mt-4">
          <div>
            <span class="text-sm font-medium">Current tags</span>
            <div class="flex flex-wrap gap-1.5 mt-1">
              <span
                :for={lt <- @duplicate_link.link_tags}
                class="badge badge-sm badge-outline"
              >
                {lt.tag.name}
              </span>
            </div>
          </div>

          <div>
            <span class="text-sm font-medium">Tags to add or refresh</span>
            <div class="flex flex-wrap gap-1.5 mt-1">
              <span
                :for={tag <- duplicate_pending_tags(@tags, @pending_tag_ids)}
                class="badge badge-sm badge-primary"
              >
                {tag.name}
              </span>
            </div>
          </div>
        </div>

        <p class="text-sm text-base-content/60 mt-4">
          Merging adds new tags, refreshes expiry on selected tags, and keeps other existing tags unchanged.
        </p>

        <div class="flex gap-2 mt-4">
          <.button variant="primary" phx-click="confirm_duplicate_merge" phx-disable-with="Merging…">
            Merge tags
          </.button>
          <.button phx-click="discard_duplicate">Discard</.button>
        </div>
      </.modal>

      <.modal
        id="edit-link-modal"
        show={@live_action == :edit}
        on_cancel={JS.patch(~p"/")}
        show_close={false}
        box_class="sm:max-w-xl"
      >
        <:title>Edit Link</:title>
        <.form
          :if={@edit_form}
          for={@edit_form}
          id="edit-link-form"
          phx-change="validate_edit"
          phx-submit="save_edit"
        >
          <.input field={@edit_form[:url]} type="url" label="URL" placeholder="https://…" />
          <.input field={@edit_form[:title]} type="text" label="Title (optional)" />
          <.input
            field={@edit_form[:note]}
            type="textarea"
            label="Note (optional)"
            placeholder="Add a short note…"
            rows="3"
            maxlength="500"
          />

          <div class="flex gap-2 mt-4">
            <.button variant="primary" phx-disable-with="Saving…">Save</.button>
            <.button patch={~p"/"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <.modal
        id="tags-modal"
        show={@live_action in [:manage_tags, :new_tag, :edit_tag]}
        on_cancel={JS.patch(~p"/")}
        box_class="sm:max-w-lg"
      >
        <:title>Manage Tags</:title>
        <.live_component
          module={LiminalWeb.TagLive.Index}
          id="tags-manager"
          current_scope={@current_scope}
          action={@live_action}
          tag_id={@tag_id}
        />
      </.modal>
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
      |> assign(:link, link)
      |> assign(:selected_tag_ids, [])
      |> assign(:form, to_form(Links.change_link(link)))
      |> assign(:editing_link, nil)
      |> assign(:edit_form, nil)
      |> assign(:tag_id, nil)
      |> assign(:shortcut_platform, nil)
      |> assign(:show_keyboard_shortcut_hints, false)
      |> assign(:duplicate_link, nil)
      |> assign(:pending_link_params, nil)
      |> assign(:pending_tag_ids, [])
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
    if matches_filters?(link, socket.assigns) do
      if socket.assigns.sort == :time_added_desc do
        {:noreply, stream_insert(socket, :links, link, at: 0)}
      else
        {:noreply, refetch_links(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({LiminalWeb.TagLive.Index, :tags_changed}, socket) do
    tags = Links.list_tags(socket.assigns.current_scope)
    {:noreply, assign(socket, :tags, tags)}
  end

  def handle_info({:link_updated, link}, socket) do
    if matches_filters?(link, socket.assigns) do
      if socket.assigns.sort == :time_added_desc do
        {:noreply, stream_insert(socket, :links, link)}
      else
        {:noreply, refetch_links(socket)}
      end
    else
      {:noreply, stream_delete(socket, :links, link)}
    end
  end

  @impl true
  def handle_event("validate", %{"link" => link_params}, socket) do
    changeset =
      socket.assigns.link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("validate_edit", %{"edit_link" => link_params}, socket) do
    changeset =
      socket.assigns.editing_link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :edit_form, to_form(changeset, as: :edit_link))}
  end

  def handle_event("toggle_tag", %{"id" => tag_id}, socket) do
    {:noreply, toggle_selected_tag(socket, tag_id)}
  end

  def handle_event("set_shortcut_platform", params, socket) do
    {:noreply,
     socket
     |> assign(:shortcut_platform, parse_shortcut_platform(params["platform"]))
     |> assign(:show_keyboard_shortcut_hints, show_keyboard_shortcut_hints?(params))}
  end

  def handle_event("shortcut_focus_new_link", _params, socket) do
    {:noreply, push_event(socket, "focus-new-link-url", %{scroll: true})}
  end

  def handle_event("shortcut_paste_link", %{"url" => url}, socket) do
    url = normalize_pasted_url(url)

    changeset =
      socket.assigns.link
      |> Links.change_link(%{"url" => url})
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> push_event("focus-new-link-url", %{scroll: true})}
  end

  def handle_event("shortcut_paste_no_link", _params, socket) do
    {:noreply, put_flash(socket, :error, "Clipboard does not contain a link")}
  end

  def handle_event("shortcut_toggle_tag_by_index", %{"index" => index}, socket) do
    case index_to_tag(index, socket.assigns.tags) do
      nil -> {:noreply, socket}
      tag -> {:noreply, toggle_selected_tag(socket, tag.id)}
    end
  end

  def handle_event("handle_shortcut_keydown", params, socket) do
    maybe_handle_shortcut_keydown(socket, params)
  end

  def handle_event("save", %{"link" => link_params}, socket) do
    save_link(socket, socket.assigns.live_action, link_params)
  end

  def handle_event("confirm_duplicate_merge", _params, socket) do
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

  def handle_event("discard_duplicate", _params, socket) do
    {:noreply, clear_duplicate_state(socket)}
  end

  def handle_event("save_edit", %{"edit_link" => link_params}, socket) do
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

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)
    {:ok, _} = Links.delete_link(scope, link)

    {:noreply, stream_delete(socket, :links, link)}
  end

  def handle_event("retry_indexing", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)

    case Links.retry_indexing(scope, link) do
      {:ok, updated_link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Indexing retry queued")
         |> stream_insert(:links, updated_link)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not retry indexing")}
    end
  end

  def handle_event("open_link", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.auto_mark_viewed do
      link = Links.get_link!(scope, id)

      if is_nil(link.viewed_at) do
        {:ok, _} = Links.mark_viewed(scope, link)
        updated_link = Links.get_link!(scope, id)
        {:noreply, stream_insert(socket, :links, updated_link)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_viewed", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)
    {:ok, _} = Links.mark_viewed(scope, link)
    updated_link = Links.get_link!(scope, id)

    {:noreply, stream_insert(socket, :links, updated_link)}
  end

  def handle_event("mark_unviewed", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)
    {:ok, _} = Links.mark_unviewed(scope, link)
    updated_link = Links.get_link!(scope, id)

    {:noreply, stream_insert(socket, :links, updated_link)}
  end

  def handle_event("tag", %{"link-id" => link_id, "tag-id" => tag_id}, socket) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, link_id)
    tag = Links.get_tag!(scope, tag_id)
    {:ok, _} = Links.tag_link(scope, link, tag)
    updated_link = Links.get_link!(scope, link_id)

    {:noreply, stream_insert(socket, :links, updated_link)}
  end

  def handle_event("untag", %{"link-id" => link_id, "tag-id" => tag_id}, socket) do
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

  def handle_event("filter", %{"filter" => filter_str}, socket) do
    filter = String.to_existing_atom(filter_str)
    {:noreply, socket |> assign(:filter, filter) |> refetch_links()}
  end

  def handle_event("sort", %{"sort" => sort_str}, socket) do
    sort = String.to_existing_atom(sort_str)
    {:noreply, socket |> assign(:sort, sort) |> refetch_links()}
  end

  def handle_event("toggle_filter_tag", %{"id" => tag_id}, socket) do
    current = socket.assigns.filter_tag_ids
    updated = if tag_id in current, do: List.delete(current, tag_id), else: [tag_id | current]
    {:noreply, socket |> assign(:filter_tag_ids, updated) |> refetch_links()}
  end

  defp maybe_handle_shortcut_keydown(
         socket,
         %{
           "key" => key,
           "code" => code,
           "shiftKey" => true,
           "altKey" => false,
           "repeat" => false
         } = params
       ) do
    with true <- mod_key_active?(params),
         {:ok, index} <- parse_digit_shortcut(key, code),
         tag when not is_nil(tag) <- Enum.at(socket.assigns.tags, index - 1) do
      {:noreply, toggle_selected_tag(socket, tag.id)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp maybe_handle_shortcut_keydown(socket, _params), do: {:noreply, socket}

  defp mod_key_active?(params) do
    platform = String.downcase(params["platform"] || "")
    ctrl_key = params["ctrlKey"] == true
    meta_key = params["metaKey"] == true

    cond do
      String.contains?(platform, "win") ->
        ctrl_key

      String.contains?(platform, "mac") ->
        meta_key

      true ->
        meta_key or ctrl_key
    end
  end

  defp parse_digit_shortcut(_key, <<"Digit", digit::binary-size(1)>>)
       when digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {:ok, String.to_integer(digit)}
  end

  defp parse_digit_shortcut(_key, <<"Numpad", digit::binary-size(1)>>)
       when digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {:ok, String.to_integer(digit)}
  end

  defp parse_digit_shortcut(key, _code) when is_binary(key) do
    case Integer.parse(key) do
      {digit, ""} when digit >= 1 and digit <= 9 -> {:ok, digit}
      _ -> :error
    end
  end

  defp parse_digit_shortcut(_key, _code), do: :error

  defp index_to_tag(index, tags) when is_integer(index), do: Enum.at(tags, index - 1)

  defp index_to_tag(index, tags) when is_binary(index) do
    case Integer.parse(index) do
      {value, ""} -> index_to_tag(value, tags)
      _ -> nil
    end
  end

  defp index_to_tag(_index, _tags), do: nil

  defp parse_shortcut_platform("mac"), do: :mac
  defp parse_shortcut_platform("windows"), do: :windows
  defp parse_shortcut_platform("linux"), do: :linux
  defp parse_shortcut_platform(_platform), do: :linux

  defp show_keyboard_shortcut_hints?(%{"show_keyboard_shortcut_hints" => false}), do: false
  defp show_keyboard_shortcut_hints?(%{"show_keyboard_shortcut_hints" => "false"}), do: false
  defp show_keyboard_shortcut_hints?(_params), do: true

  defp shortcut_mod_label(:mac), do: "⌘"
  defp shortcut_mod_label(:linux), do: "Super"
  defp shortcut_mod_label(:windows), do: "Ctrl"

  defp shortcut_shift_label(:mac), do: "Shift"
  defp shortcut_shift_label(:linux), do: "Shift"
  defp shortcut_shift_label(:windows), do: "Shift"

  defp normalize_pasted_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    if String.match?(trimmed, ~r/^https?:\/\//i) do
      trimmed
    else
      "https://" <> trimmed
    end
  end

  defp toggle_selected_tag(socket, tag_id) do
    selected = socket.assigns.selected_tag_ids

    updated =
      if tag_id in selected do
        List.delete(selected, tag_id)
      else
        [tag_id | selected]
      end

    assign(socket, :selected_tag_ids, updated)
  end

  defp save_link(socket, :index, link_params) do
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

  defp create_new_link(socket, link_params, tag_ids) do
    scope = socket.assigns.current_scope

    case Links.create_link(scope, link_params, tag_ids) do
      {:ok, link} ->
        link = Links.get_link!(scope, link.id)
        new_link = %Liminal.Links.Link{}

        {:noreply,
         socket
         |> put_flash(:info, "Link added")
         |> stream_insert(:links, link, at: 0)
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

  defp clear_duplicate_state(socket) do
    socket
    |> assign(:duplicate_link, nil)
    |> assign(:pending_link_params, nil)
    |> assign(:pending_tag_ids, [])
  end

  defp duplicate_pending_tags(tags, pending_tag_ids) do
    pending = MapSet.new(pending_tag_ids)
    Enum.filter(tags, fn tag -> tag.id in pending end)
  end

  defp refetch_links(socket) do
    scope = socket.assigns.current_scope

    links =
      Links.list_links(scope,
        filter: socket.assigns.filter,
        sort: socket.assigns.sort,
        tag_ids: socket.assigns.filter_tag_ids
      )

    stream(socket, :links, links, reset: true)
  end

  defp matches_filters?(link, assigns) do
    matches_viewed_filter?(link, assigns.filter) and
      matches_tag_filter?(link, assigns.filter_tag_ids)
  end

  defp matches_viewed_filter?(_link, :all), do: true
  defp matches_viewed_filter?(link, :unviewed), do: is_nil(link.viewed_at)
  defp matches_viewed_filter?(link, :viewed), do: not is_nil(link.viewed_at)

  defp matches_tag_filter?(_link, []), do: true

  defp matches_tag_filter?(link, tag_ids) do
    Enum.any?(link.link_tags, fn lt -> lt.tag_id in tag_ids end)
  end

  defp time_remaining(nil), do: nil

  defp time_remaining(expires_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(expires_at, now)

    cond do
      diff_seconds <= 0 -> "Expired"
      diff_seconds < 3600 -> "Expires in #{div(diff_seconds, 60)} min"
      diff_seconds < 86_400 -> "Expires in #{div(diff_seconds, 3600)} hours"
      diff_seconds < 86_400 * 30 -> "Expires in #{div(diff_seconds, 86_400)} days"
      diff_seconds < 86_400 * 365 -> "Expires in #{div(diff_seconds, 86_400 * 30)} months"
      true -> "Expires in #{div(diff_seconds, 86_400 * 365)} years"
    end
  end

  defp index_status(link) do
    cond do
      not is_nil(link.indexed_at) ->
        :indexed

      not is_nil(link.index_gave_up_at) ->
        :gave_up

      not is_nil(link.index_next_attempt_at) and
          DateTime.compare(link.index_next_attempt_at, DateTime.utc_now(:second)) == :gt ->
        :scheduled

      true ->
        :pending
    end
  end

  defp time_until(nil), do: "soon"

  defp time_until(at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(at, now)

    cond do
      diff_seconds <= 0 -> "now"
      diff_seconds < 3600 -> "in #{div(diff_seconds, 60)} min"
      diff_seconds < 86_400 -> "in #{div(diff_seconds, 3600)} hours"
      true -> "in #{div(diff_seconds, 86_400)} days"
    end
  end

  defp format_datetime(nil), do: "unknown"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end
end
