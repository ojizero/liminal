defmodule LiminalWeb.LinkLive.ToolbarComponents do
  @moduledoc false

  use LiminalWeb, :html

  import LiminalWeb.LinkLive.QueryAssigns, only: [search_input_describedby: 1]

  import LiminalWeb.LinkLive.Shortcuts,
    only: [
      focus_search_aria_keyshortcuts: 0,
      random_aria_keyshortcuts: 0
    ]

  def toolbar(assigns) do
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
    """
  end
end
