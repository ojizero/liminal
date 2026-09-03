defmodule LiminalWeb.LinkLive.Components do
  use LiminalWeb, :html

  alias Liminal.Links

  import LiminalWeb.LinkLive.Filters, only: [search_input_describedby: 1]
  import LiminalWeb.LinkLive.Formatters
  import LiminalWeb.LinkLive.LinkForms, only: [duplicate_pending_tags: 2]
  import LiminalWeb.LinkLive.Shortcuts

  def page_header(assigns) do
    ~H"""
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
    """
  end

  def search_form(assigns) do
    ~H"""
    <form
      phx-change="search"
      phx-submit="search_submit"
      id="link-search-form"
      role="search"
      class="mb-4"
    >
      <p id="link-search-hint" class="sr-only">
        Filters links by title, note, description, or URL. Typos are allowed.
      </p>
      <.input
        id="link-search-input"
        name="query"
        type="text"
        inputmode="search"
        enterkeyhint="search"
        autocomplete="off"
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
    """
  end

  def filters_and_sort(assigns) do
    ~H"""
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
    """
  end

  def tag_filter_chips(assigns) do
    ~H"""
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
    """
  end

  def masonry(assigns) do
    ~H"""
    <%!-- Links (masonry) --%>
    <div
      id="masonry"
      phx-hook="Masonry"
      class="relative"
    >
      <.new_link_card
        form={@form}
        tags={@tags}
        selected_tag_ids={@selected_tag_ids}
        shortcut_platform={@shortcut_platform}
        show_keyboard_shortcut_hints={@show_keyboard_shortcut_hints}
        show_clipboard_paste_button={@show_clipboard_paste_button}
        clipboard_has_link={@clipboard_has_link}
      />
      <.links_stream
        streams={@streams}
        tags={@tags}
        removing_link_ids={@removing_link_ids}
        auto_mark_viewed={@auto_mark_viewed}
        search_query={@search_query}
        expiry_pause={@expiry_pause}
      />
    </div>
    """
  end

  def new_link_card(assigns) do
    ~H"""
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
                <kbd
                  class={[
                    "kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80",
                    @shortcut_platform == :mac && "kbd-mod-symbol"
                  ]}
                  data-shortcut-mod="control"
                >
                  {tag_toggle_ctrl_label(@shortcut_platform)}
                </kbd>
                <kbd
                  class={[
                    "kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80",
                    @shortcut_platform == :mac && "kbd-mod-symbol"
                  ]}
                  data-shortcut-mod="shift"
                >
                  {tag_toggle_shift_label(@shortcut_platform)}
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
                  aria-keyshortcuts={@shortcut_platform && tag_toggle_aria_keyshortcuts(idx)}
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
    """
  end

  def links_stream(assigns) do
    ~H"""
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
      <.link_card
        :for={{id, link} <- @streams.links}
        id={id}
        link={link}
        tags={@tags}
        removing_link_ids={@removing_link_ids}
        auto_mark_viewed={@auto_mark_viewed}
        expiry_pause={@expiry_pause}
      />
    </div>
    """
  end

  def link_card(assigns) do
    ~H"""
    <div
      id={@id}
      data-masonry-item
      class={[
        "card bg-base-200 transition-all duration-500 ease-out",
        @link.viewed_at && !MapSet.member?(@removing_link_ids, @link.id) && "opacity-60",
        MapSet.member?(@removing_link_ids, @link.id) &&
          "opacity-0 scale-95 -translate-y-1 pointer-events-none"
      ]}
    >
      <div :if={@link.image_path} class="relative h-56 w-full shrink-0 overflow-hidden">
        <img
          src={"/#{@link.image_path}"}
          alt=""
          class="h-full w-full object-cover"
          loading="lazy"
        />
        <span
          :if={@link.duration_seconds}
          id={"link-duration-#{@link.id}"}
          class="absolute bottom-2 right-2 rounded bg-black/80 px-1.5 py-0.5 text-xs font-medium tabular-nums text-white shadow-sm"
          aria-label={"Video length #{format_video_duration(@link.duration_seconds)}"}
        >
          {format_video_duration(@link.duration_seconds)}
        </span>
      </div>

      <div class="card-body p-4 gap-2">
        <a
          href={@link.url}
          target="_blank"
          rel="noopener noreferrer"
          phx-click={@auto_mark_viewed && "open_link"}
          phx-value-id={@link.id}
          aria-label={"Open #{link_display_title(@link)} (opens in new tab)"}
          class="font-bold line-clamp-2 hover:underline"
        >
          {link_display_title(@link)}
        </a>

        <%= case index_status(@link) do %>
          <% :pending -> %>
            <span
              class="badge badge-sm badge-ghost gap-1 w-fit"
              role="status"
              aria-live="polite"
            >
              <.icon name="hero-arrow-path" class="size-3 animate-spin" /> Fetching metadata…
            </span>
          <% :scheduled -> %>
            <.with_tooltip tip={"Next attempt #{format_datetime(@link.index_next_attempt_at)}"}>
              <span
                class="badge badge-sm badge-ghost w-fit"
                role="status"
                aria-live="polite"
                aria-label={"Retry scheduled, next attempt #{format_datetime(@link.index_next_attempt_at)}"}
              >
                Retry scheduled · {time_until(@link.index_next_attempt_at)}
              </span>
            </.with_tooltip>
          <% :gave_up -> %>
            <div class="flex flex-wrap items-center gap-2">
              <.with_tooltip tip={"Gave up #{format_datetime(@link.index_gave_up_at)} after #{@link.index_attempt_count} attempts"}>
                <span
                  class="badge badge-sm badge-warning w-fit"
                  role="status"
                  aria-live="polite"
                  aria-label={"Indexing failed, gave up #{format_datetime(@link.index_gave_up_at)} after #{@link.index_attempt_count} attempts"}
                >
                  Indexing failed
                </span>
              </.with_tooltip>
              <button
                phx-click="retry_indexing"
                phx-value-id={@link.id}
                class="btn btn-xs btn-outline"
                phx-disable-with="Retrying…"
              >
                Retry indexing
              </button>
            </div>
          <% :indexed -> %>
        <% end %>

        <p :if={@link.description} class="text-sm text-base-content/70 line-clamp-3">
          {@link.description}
        </p>

        <div class="flex flex-wrap gap-1.5 mt-1">
          <.with_tooltip :for={lt <- @link.link_tags} tip={tag_expiry_label(lt, @expiry_pause)}>
            <span class="badge badge-sm badge-outline gap-1">
              {lt.tag.name}
              <.with_tooltip tip={"Remove #{lt.tag.name}"}>
                <button
                  phx-click="untag"
                  phx-value-link-id={@link.id}
                  phx-value-tag-id={lt.tag_id}
                  aria-label={"Remove tag #{lt.tag.name} from link"}
                  class="hover:text-error"
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </.with_tooltip>
            </span>
          </.with_tooltip>

          <% assigned_ids = Enum.map(@link.link_tags, & &1.tag_id) %>
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
                    phx-value-link-id={@link.id}
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
          :if={@link.note && @link.note != ""}
          class="border-l-3 border-info/60 pl-2.5 text-xs text-base-content/50 italic"
        >
          {@link.note}
        </blockquote>

        <div class="flex items-center gap-2 mt-auto pt-2 border-t border-base-300 text-xs text-base-content/50">
          <%= if @link.favicon_url do %>
            <img src={@link.favicon_url} class="size-4 rounded" alt="" />
          <% end %>
          <span class="truncate text-base-content/50">
            {link_host(@link)}
          </span>

          <%= if expiry = Links.link_expires_at(@link, @expiry_pause) do %>
            <% paused? = Links.expiry_paused?(@expiry_pause) %>
            <.with_tooltip tip={expiry_tooltip(expiry, @expiry_pause)}>
              <span
                id={"link-expiry-#{@link.id}"}
                class={[
                  "flex items-center gap-1 shrink-0",
                  if(paused?, do: "text-warning/80", else: "text-base-content/45")
                ]}
                aria-label={expiry_tooltip(expiry, @expiry_pause)}
              >
                <.icon
                  name={if(paused?, do: "hero-pause-circle", else: "hero-clock")}
                  class="size-3.5"
                />
                {expiry_label(expiry, @expiry_pause)}
              </span>
            </.with_tooltip>
          <% end %>

          <div class="flex gap-1 ml-auto shrink-0">
            <.with_tooltip tip={if(@link.viewed_at, do: "Mark unviewed", else: "Mark viewed")}>
              <button
                phx-click={if(@link.viewed_at, do: "mark_unviewed", else: "mark_viewed")}
                phx-value-id={@link.id}
                aria-label={mark_viewed_label(@link)}
                class="btn btn-ghost btn-xs btn-circle"
              >
                <.icon
                  name={if(@link.viewed_at, do: "hero-eye-slash", else: "hero-eye")}
                  class="size-3.5"
                />
              </button>
            </.with_tooltip>
            <.with_tooltip tip="Edit">
              <.link
                patch={~p"/links/#{@link.id}/edit"}
                aria-label={"Edit #{link_display_title(@link)}"}
                class="btn btn-ghost btn-xs btn-circle"
              >
                <.icon name="hero-pencil-square" class="size-3.5" />
              </.link>
            </.with_tooltip>
            <.with_tooltip tip="Delete">
              <button
                phx-click="delete"
                phx-value-id={@link.id}
                data-confirm="Are you sure?"
                aria-label={"Delete #{link_display_title(@link)}"}
                class="btn btn-ghost btn-xs btn-circle hover:text-error"
              >
                <.icon name="hero-trash" class="size-3.5" />
              </button>
            </.with_tooltip>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def duplicate_modal(assigns) do
    ~H"""
    <.modal
      id="duplicate-link-modal"
      show={@duplicate_link != nil}
      on_cancel={JS.push("discard_duplicate")}
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

      <div class="mt-4">
        <.button variant="primary" phx-click="confirm_duplicate_merge" phx-disable-with="Merging…">
          Merge tags
        </.button>
      </div>
    </.modal>
    """
  end

  def edit_modal(assigns) do
    ~H"""
    <.modal
      id="edit-link-modal"
      show={@live_action == :edit}
      on_cancel={JS.patch(~p"/")}
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

        <div class="mt-4">
          <.button variant="primary" phx-disable-with="Saving…">Save</.button>
        </div>
      </.form>
    </.modal>
    """
  end

  def tag_manager_modal(assigns) do
    ~H"""
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
    """
  end
end
