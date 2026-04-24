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
          <.button navigate={~p"/tags"}>Tags</.button>
          <.button variant="primary" patch={~p"/links/new"}>
            <.icon name="hero-plus" class="size-4" /> Add Link
          </.button>
        </:actions>
      </.header>

      <%!-- Filter buttons --%>
      <div class="flex gap-2 mb-4">
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

      <%!-- Inline form for new/edit --%>
      <div :if={@live_action in [:new, :edit]} class="mb-6 p-4 bg-base-200 rounded-lg">
        <.form for={@form} id="link-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:url]} type="url" label="URL" placeholder="https://..." />
          <.input field={@form[:title]} type="text" label="Title (optional)" />

          <%= if @live_action == :new do %>
            <div class="mt-3">
              <span class="text-sm font-medium">Tags</span>
              <div class="flex flex-wrap gap-3 mt-1">
                <label
                  :for={tag <- @tags}
                  class="inline-flex items-center gap-2 cursor-pointer select-none"
                >
                  <input
                    type="checkbox"
                    checked={tag.id in @selected_tag_ids}
                    phx-click="toggle_tag"
                    phx-value-id={tag.id}
                    class={[
                      "h-4 w-4 rounded border border-gray-400 text-indigo-600",
                      "focus:ring-2 focus:ring-indigo-500 focus:ring-offset-1",
                      "transition-colors duration-150"
                    ]}
                  />
                  <span class="text-sm">{tag.name}</span>
                </label>
              </div>
            </div>
          <% end %>

          <div class="flex gap-2 mt-2">
            <.button variant="primary" phx-disable-with="Saving...">Save</.button>
            <.button patch={~p"/"}>Cancel</.button>
          </div>
        </.form>
      </div>

      <%!-- Links stream --%>
      <ul id="links" phx-update="stream" class="space-y-3">
        <li id="links-empty" class="hidden only:block text-center py-8 text-base-content/50">
          No links yet. Add one above!
        </li>
        <li
          :for={{id, link} <- @streams.links}
          id={id}
          class={[
            "p-4 bg-base-200 rounded-lg flex items-start gap-3 group",
            link.viewed_at && "opacity-60"
          ]}
        >
          <%!-- Viewed toggle --%>
          <button
            phx-click={if(link.viewed_at, do: "mark_unviewed", else: "mark_viewed")}
            phx-value-id={link.id}
            class="btn btn-ghost btn-sm btn-circle mt-0.5 shrink-0"
            title={if(link.viewed_at, do: "Mark unviewed", else: "Mark viewed")}
          >
            <.icon
              name={if(link.viewed_at, do: "hero-check-circle-solid", else: "hero-circle")}
              class="size-5"
            />
          </button>

          <%!-- Link content --%>
          <div class="flex-1 min-w-0">
            <div class="font-medium truncate">
              {link.title || link.url}
            </div>
            <a
              href={link.url}
              target="_blank"
              rel="noopener noreferrer"
              class="text-sm text-primary hover:underline truncate block"
            >
              {link.url}
            </a>

            <%!-- Tag badges --%>
            <div class="flex flex-wrap gap-1.5 mt-2">
              <span
                :for={lt <- link.link_tags}
                class="badge badge-sm badge-outline gap-1"
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

              <%!-- Add tag dropdown --%>
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
                    >
                      {tag.name}
                    </button>
                  </li>
                </ul>
              </details>
            </div>
          </div>

          <%!-- Actions --%>
          <div class="flex gap-1 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
            <.button patch={~p"/links/#{link.id}/edit"} class="btn btn-ghost btn-sm btn-circle">
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <button
              phx-click="delete"
              phx-value-id={link.id}
              data-confirm="Are you sure?"
              class="btn btn-ghost btn-sm btn-circle hover:text-error"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    tags = Links.list_tags(scope)
    links = Links.list_links(scope, filter: :unviewed)

    socket =
      socket
      |> assign(:tags, tags)
      |> assign(:filter, :unviewed)
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
    |> assign(:link, nil)
    |> assign(:form, nil)
    |> assign(:selected_tag_ids, [])
  end

  defp apply_action(socket, :new, _params) do
    link = %Liminal.Links.Link{}

    socket
    |> assign(:page_title, "Add Link")
    |> assign(:link, link)
    |> assign(:selected_tag_ids, [])
    |> assign(:form, to_form(Links.change_link(link)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    link = Links.get_link!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Link")
    |> assign(:link, link)
    |> assign(:selected_tag_ids, [])
    |> assign(:form, to_form(Links.change_link(link)))
  end

  @impl true
  def handle_event("validate", %{"link" => link_params}, socket) do
    changeset =
      socket.assigns.link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
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
    scope = socket.assigns.current_scope
    links = Links.list_links(scope, filter: filter)

    socket =
      socket
      |> assign(:filter, filter)
      |> stream(:links, links, reset: true)

    {:noreply, socket}
  end

  defp save_link(socket, :new, link_params) do
    scope = socket.assigns.current_scope
    tag_ids = socket.assigns.selected_tag_ids

    case Links.create_link(scope, link_params, tag_ids) do
      {:ok, link} ->
        link = Links.get_link!(scope, link.id)

        {:noreply,
         socket
         |> put_flash(:info, "Link added")
         |> stream_insert(:links, link, at: 0)
         |> push_patch(to: ~p"/")}

      {:error, :no_tags} ->
        {:noreply, put_flash(socket, :error, "Select at least one tag")}

      {:error, :invalid_tags} ->
        {:noreply, put_flash(socket, :error, "One or more selected tags are invalid")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_link(socket, :edit, link_params) do
    scope = socket.assigns.current_scope

    case Links.update_link(scope, socket.assigns.link, link_params) do
      {:ok, link} ->
        link = Links.get_link!(scope, link.id)

        {:noreply,
         socket
         |> put_flash(:info, "Link updated")
         |> stream_insert(:links, link)
         |> push_patch(to: ~p"/")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
