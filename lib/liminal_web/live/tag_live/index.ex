defmodule LiminalWeb.TagLive.Index do
  use LiminalWeb, :live_view

  alias Liminal.Links

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Tags
        <:actions>
          <.button navigate={~p"/"}>Back to Links</.button>
          <.button variant="primary" patch={~p"/tags/new"}>
            <.icon name="hero-plus" class="size-4" /> New Tag
          </.button>
        </:actions>
      </.header>

      <%!-- Inline form for new/edit --%>
      <div :if={@live_action in [:new, :edit]} class="mb-6 p-4 bg-base-200 rounded-lg">
        <.form for={@form} id="tag-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:expires_in_days]} type="number" label="Expires in (days)" />
          <div class="flex gap-2 mt-2">
            <.button variant="primary" phx-disable-with="Saving...">Save</.button>
            <.button patch={~p"/tags"}>Cancel</.button>
          </div>
        </.form>
      </div>

      <%!-- Tags stream --%>
      <ul id="tags" phx-update="stream" class="space-y-3">
        <li id="tags-empty" class="hidden only:block text-center py-8 text-base-content/50">
          No tags yet. Create one above!
        </li>
        <li
          :for={{id, tag} <- @streams.tags}
          id={id}
          class="p-4 bg-base-200 rounded-lg flex items-center justify-between group"
        >
          <div>
            <span class="font-medium">{tag.name}</span>
            <span class="text-sm text-base-content/60 ml-2">
              {tag.expires_in_days} days
            </span>
          </div>
          <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <.button
              patch={~p"/tags/#{tag.id}/edit"}
              class="btn btn-ghost btn-sm btn-circle"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <button
              phx-click="delete"
              phx-value-id={tag.id}
              data-confirm="Are you sure? Links tagged with this tag will lose the tag."
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

    {:ok, stream(socket, :tags, tags)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Tags")
    |> assign(:tag, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    tag = %Liminal.Links.Tag{}

    socket
    |> assign(:page_title, "New Tag")
    |> assign(:tag, tag)
    |> assign(:form, to_form(Links.change_tag(tag)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    tag = Links.get_tag!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Tag")
    |> assign(:tag, tag)
    |> assign(:form, to_form(Links.change_tag(tag)))
  end

  @impl true
  def handle_event("validate", %{"tag" => tag_params}, socket) do
    changeset =
      socket.assigns.tag
      |> Links.change_tag(tag_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"tag" => tag_params}, socket) do
    save_tag(socket, socket.assigns.live_action, tag_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    tag = Links.get_tag!(scope, id)
    {:ok, _} = Links.delete_tag(scope, tag)

    {:noreply, stream_delete(socket, :tags, tag)}
  end

  defp save_tag(socket, :new, tag_params) do
    scope = socket.assigns.current_scope

    case Links.create_tag(scope, tag_params) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag created")
         |> stream_insert(:tags, tag)
         |> push_patch(to: ~p"/tags")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_tag(socket, :edit, tag_params) do
    scope = socket.assigns.current_scope

    case Links.update_tag(scope, socket.assigns.tag, tag_params) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag updated")
         |> stream_insert(:tags, tag)
         |> push_patch(to: ~p"/tags")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
