defmodule LiminalWeb.LinkLive.Index do
  use LiminalWeb, :live_view

  alias Liminal.Links

  @viewed_removal_delay_ms 1_000
  @viewed_removal_transition_ms 500

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:links}>
      <.header>
        My Links
        <:actions>
          <.with_tooltip tip="Open a random saved link">
            <.button
              href={~p"/links/random"}
              id="random-link"
              target="_blank"
              rel="noopener noreferrer"
              variant="soft"
              aria-label="Open a random saved link (opens in new tab)"
              aria-keyshortcuts={@shortcut_platform && random_aria_keyshortcuts()}
            >
              <span class="inline-flex items-center gap-2">
                <.icon name="hero-arrow-path" class="size-4" /> Random
                <span
                  :if={@shortcut_platform && @show_keyboard_shortcut_hints}
                  id="random-link-shortcut"
                  class="inline-flex items-center"
                >
                  <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                    R
                  </kbd>
                </span>
              </span>
            </.button>
          </.with_tooltip>
          <.button patch={~p"/tags"} variant="soft">Manage Tags</.button>
        </:actions>
      </.header>

      <form phx-change="search" phx-submit="search" id="link-search-form" role="search" class="mb-4">
        <p id="link-search-hint" class="sr-only">
          Filters links by title, note, description, or URL. Typos are allowed.
        </p>
        <.input
          id="link-search-input"
          name="query"
          type="search"
          label="Search"
          value={@search_query}
          placeholder="Title, note, description, or URL…"
          phx-debounce="300"
          fieldset_class="mb-0"
          class={@shortcut_platform && @show_keyboard_shortcut_hints && "pr-12"}
          aria-controls="links"
          aria-describedby={search_input_describedby(@search_query)}
          aria-keyshortcuts={@shortcut_platform && focus_search_aria_keyshortcuts()}
        >
          <:suffix :if={@shortcut_platform && @show_keyboard_shortcut_hints}>
            <div
              id="link-search-focus-shortcut"
              class="pointer-events-none absolute inset-y-0 right-2 flex items-center gap-0.5"
            >
              <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                F
              </kbd>
            </div>
          </:suffix>
        </.input>
        <p
          :if={@search_query != ""}
          id="link-search-status"
          class="sr-only"
          role="status"
          aria-live="polite"
          aria-atomic="true"
        >
          {@search_results_count} {if @search_results_count == 1, do: "link", else: "links"} match your search.
        </p>
      </form>

      <%!-- Filter buttons and sort control --%>
      <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-2">
        <div class="flex flex-wrap gap-2" role="group" aria-label="Filter links by view status">
          <button
            :for={filter <- [:unviewed, :all, :viewed]}
            phx-click="filter"
            phx-value-filter={filter}
            aria-pressed={@filter == filter}
            class={[
              "btn btn-sm",
              if(@filter == filter, do: "btn-primary", else: "btn-ghost")
            ]}
          >
            {filter |> Atom.to_string() |> String.capitalize()}
          </button>
        </div>

        <div class="flex items-center gap-2 sm:ml-auto">
          <label for="sort-select" class="text-sm text-base-content/60 shrink-0">Sort:</label>
          <form phx-change="sort" id="sort-form" class="min-w-0 flex-1 sm:flex-none">
            <select
              id="sort-select"
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
      <div
        :if={@tags != []}
        class="flex flex-wrap gap-2 mb-4"
        role="group"
        aria-label="Filter by tags"
      >
        <span class="text-sm text-base-content/60 self-center mr-1">Tags:</span>
        <button
          :for={tag <- @tags}
          phx-click="toggle_filter_tag"
          phx-value-id={tag.id}
          aria-pressed={tag.id in @filter_tag_ids}
          aria-label={"Filter by #{tag.name}"}
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
                  type="text"
                  inputmode="url"
                  placeholder="example.com or https://…"
                  phx-debounce="300"
                  fieldset_class="mb-0"
                  class={@shortcut_platform && @show_keyboard_shortcut_hints && "pr-12"}
                  aria-keyshortcuts={
                    @shortcut_platform && focus_url_aria_keyshortcuts(@shortcut_platform)
                  }
                >
                  <:suffix :if={@shortcut_platform && @show_keyboard_shortcut_hints}>
                    <div
                      id="link-url-focus-shortcut"
                      class="pointer-events-none absolute inset-y-0 right-2 flex items-center gap-0.5"
                    >
                      <kbd class="kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80">
                        J
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
                    <span
                      class="text-xs text-base-content/45"
                      aria-label="Paste a copied URL from clipboard. Works when not focused in an input."
                      aria-keyshortcuts={
                        @shortcut_platform && paste_aria_keyshortcuts(@shortcut_platform)
                      }
                    >
                      Paste from anywhere
                    </span>
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
                <div
                  :if={
                    @shortcut_platform && !@show_keyboard_shortcut_hints &&
                      @show_clipboard_paste_button
                  }
                  class="mt-2"
                >
                  <.button
                    type="button"
                    id="link-url-paste-from-clipboard"
                    variant="soft"
                    class="btn-sm w-full"
                    disabled={!@clipboard_has_link}
                  >
                    <.icon name="hero-clipboard-document" class="size-4" /> Paste from clipboard
                  </.button>
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
                  class="w-full textarea resize-none"
                  aria-keyshortcuts={
                    @shortcut_platform && save_note_aria_keyshortcuts(@shortcut_platform)
                  }
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
                      aria-pressed={tag.id in @selected_tag_ids}
                      aria-label={"#{tag.name}, expires in #{tag.expires_in_days} days"}
                      aria-keyshortcuts={
                        @shortcut_platform && tag_toggle_aria_keyshortcuts(@shortcut_platform, idx)
                      }
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

        <div id="links" phx-update="stream" class="contents" role="region" aria-label="Link results">
          <div
            id="links-empty"
            role="status"
            class="hidden only:block text-center py-8 text-base-content/50"
          >
            <%= if @search_query != "" do %>
              No links match your search.
            <% else %>
              No links yet. Add one above!
            <% end %>
          </div>
          <div
            :for={{id, link} <- @streams.links}
            id={id}
            data-masonry-item
            class={[
              "card bg-base-200 transition-all duration-500 ease-out",
              link.viewed_at && !MapSet.member?(@removing_link_ids, link.id) && "opacity-60",
              MapSet.member?(@removing_link_ids, link.id) &&
                "opacity-0 scale-95 -translate-y-1 pointer-events-none"
            ]}
          >
            <div :if={link.image_path} class="relative h-56 w-full shrink-0 overflow-hidden">
              <img
                src={"/#{link.image_path}"}
                alt=""
                class="h-full w-full object-cover"
                loading="lazy"
              />
              <span
                :if={link.duration_seconds}
                id={"link-duration-#{link.id}"}
                class="absolute bottom-2 right-2 rounded bg-black/80 px-1.5 py-0.5 text-xs font-medium tabular-nums text-white shadow-sm"
                aria-label={"Video length #{format_video_duration(link.duration_seconds)}"}
              >
                {format_video_duration(link.duration_seconds)}
              </span>
            </div>

            <div class="card-body p-4 gap-2">
              <a
                href={link.url}
                target="_blank"
                rel="noopener noreferrer"
                phx-click={@auto_mark_viewed && "open_link"}
                phx-value-id={link.id}
                aria-label={"Open #{link_display_title(link)} (opens in new tab)"}
                class="font-bold line-clamp-2 hover:underline"
              >
                {link_display_title(link)}
              </a>

              <%= case index_status(link) do %>
                <% :pending -> %>
                  <span
                    class="badge badge-sm badge-ghost gap-1 w-fit"
                    role="status"
                    aria-live="polite"
                  >
                    <.icon name="hero-arrow-path" class="size-3 animate-spin" /> Fetching metadata…
                  </span>
                <% :scheduled -> %>
                  <.with_tooltip tip={"Next attempt #{format_datetime(link.index_next_attempt_at)}"}>
                    <span
                      class="badge badge-sm badge-ghost w-fit"
                      role="status"
                      aria-live="polite"
                      aria-label={"Retry scheduled, next attempt #{format_datetime(link.index_next_attempt_at)}"}
                    >
                      Retry scheduled · {time_until(link.index_next_attempt_at)}
                    </span>
                  </.with_tooltip>
                <% :gave_up -> %>
                  <div class="flex flex-wrap items-center gap-2">
                    <.with_tooltip tip={"Gave up #{format_datetime(link.index_gave_up_at)} after #{link.index_attempt_count} attempts"}>
                      <span
                        class="badge badge-sm badge-warning w-fit"
                        role="status"
                        aria-live="polite"
                        aria-label={"Indexing failed, gave up #{format_datetime(link.index_gave_up_at)} after #{link.index_attempt_count} attempts"}
                      >
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
                        aria-label={"Remove tag #{lt.tag.name} from link"}
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
                  <summary
                    class="badge badge-sm badge-ghost cursor-pointer gap-1"
                    aria-label="Add tag"
                  >
                    <.icon name="hero-plus" class="size-3" /> tag
                  </summary>
                  <ul class="dropdown-content menu bg-base-200 rounded-box z-10 p-2 shadow mt-1">
                    <li :for={tag <- available}>
                      <.with_tooltip tip={"Expires in #{tag.expires_in_days} days"}>
                        <button
                          phx-click="tag"
                          phx-value-link-id={link.id}
                          phx-value-tag-id={tag.id}
                          aria-label={"Add tag #{tag.name}, expires in #{tag.expires_in_days} days"}
                        >
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
                <span class="truncate text-base-content/50">
                  {link_host(link)}
                </span>

                <%= if expiry = Links.link_expires_at(link) do %>
                  <.with_tooltip tip={format_datetime(expiry)}>
                    <span
                      id={"link-expiry-#{link.id}"}
                      class="flex items-center gap-1 shrink-0 text-base-content/45"
                      aria-label={"Expires #{format_datetime(expiry)}"}
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
                      aria-label={mark_viewed_label(link)}
                      class="btn btn-ghost btn-xs btn-circle"
                    >
                      <.icon
                        name={if(link.viewed_at, do: "hero-eye-slash", else: "hero-eye")}
                        class="size-3.5"
                      />
                    </button>
                  </.with_tooltip>
                  <.with_tooltip tip="Edit">
                    <.link
                      patch={~p"/links/#{link.id}/edit"}
                      aria-label={"Edit #{link_display_title(link)}"}
                      class="btn btn-ghost btn-xs btn-circle"
                    >
                      <.icon name="hero-pencil-square" class="size-3.5" />
                    </.link>
                  </.with_tooltip>
                  <.with_tooltip tip="Delete">
                    <button
                      phx-click="delete"
                      phx-value-id={link.id}
                      data-confirm="Are you sure?"
                      aria-label={"Delete #{link_display_title(link)}"}
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
        close_label="Cancel"
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
          <.input
            field={@edit_form[:url]}
            type="text"
            inputmode="url"
            label="URL"
            placeholder="example.com or https://…"
          />
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
    cond do
      matches_filters?(link, socket.assigns) ->
        socket =
          socket
          |> cancel_viewed_removal(link.id)
          |> assign(:removing_link_ids, MapSet.delete(socket.assigns.removing_link_ids, link.id))
          |> then(fn socket ->
            if socket.assigns.sort == :time_added_desc do
              stream_insert(socket, :links, link)
            else
              refetch_links(socket)
            end
          end)

        {:noreply, socket}

      leaving_unviewed_filter?(link, socket.assigns) ->
        {:noreply,
         socket
         |> stream_insert(:links, link)
         |> schedule_viewed_removal(link.id)}

      true ->
        {:noreply, stream_delete(socket, :links, link)}
    end
  end

  def handle_info({:remove_viewed_link, link_id}, socket) do
    socket = cancel_viewed_removal(socket, link_id)

    if socket.assigns.filter == :unviewed and
         not MapSet.member?(socket.assigns.removing_link_ids, link_id) do
      ref =
        Process.send_after(
          self(),
          {:complete_viewed_removal, link_id},
          @viewed_removal_transition_ms
        )

      {:noreply,
       socket
       |> assign(:removing_link_ids, MapSet.put(socket.assigns.removing_link_ids, link_id))
       |> assign(
         :pending_viewed_removals,
         Map.put(socket.assigns.pending_viewed_removals, link_id, ref)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:complete_viewed_removal, link_id}, socket) do
    socket = cancel_viewed_removal(socket, link_id)

    socket =
      socket
      |> assign(:removing_link_ids, MapSet.delete(socket.assigns.removing_link_ids, link_id))
      |> then(fn socket ->
        if socket.assigns.filter == :unviewed do
          stream_delete(socket, :links, %{id: link_id})
        else
          socket
        end
      end)

    {:noreply, socket}
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
     |> assign(:show_keyboard_shortcut_hints, show_keyboard_shortcut_hints?(params))
     |> assign(:show_clipboard_paste_button, show_clipboard_paste_button?(params))
     |> assign(:clipboard_has_link, false)}
  end

  def handle_event("set_clipboard_has_link", params, socket) do
    {:noreply, assign(socket, :clipboard_has_link, clipboard_has_link?(params))}
  end

  def handle_event("shortcut_focus_new_link", _params, socket) do
    {:noreply, push_event(socket, "focus-new-link-url", %{scroll: true})}
  end

  def handle_event("shortcut_paste_link", %{"url" => url}, socket) do
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

      {:error, :reindex_busy} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A reindex job is already running. Try again when it finishes."
         )}
    end
  end

  def handle_event("open_link", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.auto_mark_viewed do
      link = Links.get_link!(scope, id)

      if is_nil(link.viewed_at) do
        {:ok, _} = Links.mark_viewed(scope, link)
        {:noreply, socket}
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

    {:noreply, socket}
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

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query) |> refetch_links()}
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

  defp show_clipboard_paste_button?(%{"show_clipboard_paste_button" => false}), do: false
  defp show_clipboard_paste_button?(%{"show_clipboard_paste_button" => "false"}), do: false
  defp show_clipboard_paste_button?(_params), do: true

  defp clipboard_has_link?(%{"has_link" => true}), do: true
  defp clipboard_has_link?(%{"has_link" => "true"}), do: true
  defp clipboard_has_link?(_params), do: false

  defp shortcut_mod_label(:mac), do: "⌘"
  defp shortcut_mod_label(:linux), do: "Super"
  defp shortcut_mod_label(:windows), do: "Ctrl"

  defp shortcut_shift_label(:mac), do: "Shift"
  defp shortcut_shift_label(:linux), do: "Shift"
  defp shortcut_shift_label(:windows), do: "Shift"

  defp shortcut_mod_aria(:mac), do: "Meta"
  defp shortcut_mod_aria(:linux), do: "Meta"
  defp shortcut_mod_aria(:windows), do: "Control"

  defp focus_url_aria_keyshortcuts(platform) do
    mod = shortcut_mod_aria(platform)
    "J #{mod}+V"
  end

  defp paste_aria_keyshortcuts(platform), do: "#{shortcut_mod_aria(platform)}+V"

  defp focus_search_aria_keyshortcuts, do: "F"

  defp random_aria_keyshortcuts, do: "R"

  defp tag_toggle_aria_keyshortcuts(platform, index),
    do: "#{shortcut_mod_aria(platform)}+Shift+#{index}"

  defp save_note_aria_keyshortcuts(platform), do: "#{save_note_mod_aria(platform)}+Enter"

  defp save_note_mod_aria(:mac), do: "Meta"
  defp save_note_mod_aria(:linux), do: "Control"
  defp save_note_mod_aria(:windows), do: "Control"

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
         |> maybe_stream_insert_link(link)
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

    socket = cancel_all_viewed_removals(socket)

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

  defp search_input_describedby(""), do: "link-search-hint"

  defp search_input_describedby(_query), do: "link-search-hint link-search-status"

  defp maybe_stream_insert_link(socket, link) do
    if matches_filters?(link, socket.assigns) do
      if socket.assigns.sort == :time_added_desc do
        stream_insert(socket, :links, link, at: 0)
      else
        refetch_links(socket)
      end
    else
      socket
    end
  end

  defp matches_filters?(link, assigns) do
    matches_viewed_filter?(link, assigns.filter) and
      matches_tag_filter?(link, assigns.filter_tag_ids) and
      matches_search_filter?(link, assigns.search_query)
  end

  defp matches_viewed_filter?(_link, :all), do: true
  defp matches_viewed_filter?(link, :unviewed), do: is_nil(link.viewed_at)
  defp matches_viewed_filter?(link, :viewed), do: not is_nil(link.viewed_at)

  defp leaving_unviewed_filter?(link, assigns) do
    assigns.filter == :unviewed and not is_nil(link.viewed_at) and
      matches_tag_filter?(link, assigns.filter_tag_ids) and
      matches_search_filter?(link, assigns.search_query)
  end

  defp schedule_viewed_removal(socket, link_id) do
    socket = cancel_viewed_removal(socket, link_id)

    ref = Process.send_after(self(), {:remove_viewed_link, link_id}, @viewed_removal_delay_ms)

    assign(
      socket,
      :pending_viewed_removals,
      Map.put(socket.assigns.pending_viewed_removals, link_id, ref)
    )
  end

  defp cancel_viewed_removal(socket, link_id) do
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

  defp cancel_all_viewed_removals(socket) do
    for {_link_id, ref} <- socket.assigns.pending_viewed_removals do
      Process.cancel_timer(ref)
    end

    socket
    |> assign(:pending_viewed_removals, %{})
    |> assign(:removing_link_ids, MapSet.new())
  end

  defp matches_tag_filter?(_link, []), do: true

  defp matches_tag_filter?(link, tag_ids) do
    Enum.any?(link.link_tags, fn lt -> lt.tag_id in tag_ids end)
  end

  defp matches_search_filter?(_link, query) when query in [nil, ""], do: true

  defp matches_search_filter?(link, query) do
    Liminal.Links.TextSearch.matches?(link, query)
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

  defp format_video_duration(seconds) do
    Liminal.Links.Duration.format(seconds)
  end

  defp link_display_title(link), do: link.title || link.url

  defp link_host(link) do
    URI.parse(link.url).host || link.url
  end

  defp mark_viewed_label(link) do
    title = link_display_title(link)

    if link.viewed_at do
      "Mark #{title} as unviewed"
    else
      "Mark #{title} as viewed"
    end
  end
end
