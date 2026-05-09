defmodule LiminalWeb.LinkLive.Index do
  use LiminalWeb, :live_view

  alias Liminal.Links

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        My Links
        <:actions>
          <.button navigate={~p"/tags"}>Manage Tags</.button>
        </:actions>
      </.header>

      <%!-- Filter buttons and sort control --%>
      <div class="flex items-center gap-2 mb-4">
        <div class="flex gap-2">
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

        <div class="flex-1" />

        <div class="flex items-center gap-2">
          <span class="text-sm text-base-content/60">Sort:</span>
          <form phx-change="sort" id="sort-form">
            <select
              name="sort"
              class="select select-sm select-bordered"
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

      <%!-- Edit form (shown when editing a link) --%>
      <div :if={@editing_link} class="card bg-base-200 mb-6">
        <div class="card-body p-4">
          <h3 class="text-sm font-semibold mb-2">Edit Link</h3>
          <.form
            for={@edit_form}
            id="edit-link-form"
            phx-change="validate_edit"
            phx-submit="save_edit"
          >
            <.input field={@edit_form[:url]} type="url" label="URL" placeholder="https://..." />
            <.input field={@edit_form[:title]} type="text" label="Title (optional)" />

            <div class="flex gap-2 mt-2">
              <.button variant="primary" phx-disable-with="Saving...">Save</.button>
              <.button patch={~p"/"}>Cancel</.button>
            </div>
          </.form>
        </div>
      </div>

      <%!-- Links (masonry) --%>
      <div id="masonry" phx-hook="Masonry" class="relative">
        <%!-- New link card (always first in masonry) --%>
        <div
          id="new-link-card"
          data-masonry-item
          class="card bg-base-200 border border-dashed border-base-content/20"
        >
          <div class="card-body p-4">
            <.form for={@form} id="link-form" phx-change="validate" phx-submit="save">
              <.input field={@form[:url]} type="url" placeholder="https://..." />

              <div :if={@tags != []} class="mt-3">
                <span class="text-sm font-medium">Tags</span>
                <div class="flex flex-wrap gap-2 mt-1">
                  <button
                    :for={tag <- @tags}
                    type="button"
                    phx-click="toggle_tag"
                    phx-value-id={tag.id}
                    title={"Expires in #{tag.expires_in_days} days"}
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
                </div>
              </div>

              <div class="flex justify-end mt-3">
                <.button variant="primary" phx-disable-with="Saving...">
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
            <a :if={link.image_path} href={link.url} target="_blank" rel="noopener noreferrer" class="h-56 w-full shrink-0 overflow-hidden block">
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
                class="font-bold line-clamp-2 hover:underline"
              >
                {link.title || link.url}
              </a>

              <p :if={link.description} class="text-sm text-base-content/70 line-clamp-3">
                {link.description}
              </p>

              <div class="flex flex-wrap gap-1.5 mt-1">
                <span
                  :for={lt <- link.link_tags}
                  class="badge badge-sm badge-outline gap-1"
                  title={time_remaining(lt.expires_at)}
                >
                  {lt.tag.name}
                  <button
                    phx-click="untag"
                    phx-value-link-id={link.id}
                    phx-value-tag-id={lt.tag_id}
                    class="hover:text-error"
                    title={"Remove #{lt.tag.name}"}
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                </span>

                <% assigned_ids = Enum.map(link.link_tags, & &1.tag_id) %>
                <% available = Enum.reject(@tags, fn t -> t.id in assigned_ids end) %>
                <details :if={available != []} class="dropdown">
                  <summary class="badge badge-sm badge-ghost cursor-pointer gap-1">
                    <.icon name="hero-plus" class="size-3" /> tag
                  </summary>
                  <ul class="dropdown-content menu bg-base-200 rounded-box z-10 p-2 shadow mt-1">
                    <li :for={tag <- available}>
                      <button
                        phx-click="tag"
                        phx-value-link-id={link.id}
                        phx-value-tag-id={tag.id}
                        title={"Expires in #{tag.expires_in_days} days"}
                      >
                        {tag.name}
                      </button>
                    </li>
                  </ul>
                </details>
              </div>

              <div class="flex items-center gap-2 mt-auto pt-2 border-t border-base-300 text-xs text-base-content/50">
                <%= if link.favicon_url do %>
                  <img src={link.favicon_url} class="size-4 rounded" alt="" />
                <% end %>
                <a
                  href={link.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="truncate hover:underline hover:text-primary"
                >
                  {URI.parse(link.url).host || link.url}
                </a>

                <div class="flex gap-1 ml-auto shrink-0">
                  <button
                    phx-click={if(link.viewed_at, do: "mark_unviewed", else: "mark_viewed")}
                    phx-value-id={link.id}
                    class="btn btn-ghost btn-xs btn-circle"
                    title={if(link.viewed_at, do: "Mark unviewed", else: "Mark viewed")}
                  >
                    <.icon
                      name={if(link.viewed_at, do: "hero-eye-slash", else: "hero-eye")}
                      class="size-3.5"
                    />
                  </button>
                  <.link
                    patch={~p"/links/#{link.id}/edit"}
                    class="btn btn-ghost btn-xs btn-circle"
                    title="Edit"
                  >
                    <.icon name="hero-pencil-square" class="size-3.5" />
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={link.id}
                    data-confirm="Are you sure?"
                    class="btn btn-ghost btn-xs btn-circle hover:text-error"
                    title="Delete"
                  >
                    <.icon name="hero-trash" class="size-3.5" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
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
      |> assign(:filter, :unviewed)
      |> assign(:sort, :time_added_desc)
      |> assign(:filter_tag_ids, [])
      |> assign(:link, link)
      |> assign(:selected_tag_ids, [])
      |> assign(:form, to_form(Links.change_link(link)))
      |> assign(:editing_link, nil)
      |> assign(:edit_form, nil)
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
    selected = socket.assigns.selected_tag_ids

    updated =
      if tag_id in selected do
        List.delete(selected, tag_id)
      else
        [tag_id | selected]
      end

    {:noreply, assign(socket, :selected_tag_ids, updated)}
  end

  def handle_event("save", %{"link" => link_params}, socket) do
    save_link(socket, socket.assigns.live_action, link_params)
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

  defp save_link(socket, :index, link_params) do
    scope = socket.assigns.current_scope
    tag_ids = socket.assigns.selected_tag_ids

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
end
