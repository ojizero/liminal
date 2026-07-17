defmodule LiminalWeb.LinkLive.LinkCard do
  @moduledoc false

  use LiminalWeb, :html

  alias Liminal.Links

  import LiminalWeb.LinkLive.Presenters

  def stream(assigns) do
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
    """
  end
end
