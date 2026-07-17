defmodule LiminalWeb.TagLive.Index do
  @moduledoc false
  use LiminalWeb, :live_component

  alias Liminal.Links

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Inline form for new/edit --%>
      <div :if={@action in [:new_tag, :edit_tag]} class="mb-5 p-4 bg-base-200 rounded-lg">
        <.form for={@form} id="tag-form" phx-change="validate" phx-submit="save" phx-target={@myself}>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:expires_in_days]} type="number" label="Expires in (days)" />
          <div class="flex gap-2 mt-3">
            <.button variant="primary" phx-disable-with="Saving…">Save</.button>
            <.button patch={~p"/tags"}>Cancel</.button>
          </div>
        </.form>
      </div>

      <div :if={@action == :manage_tags} class="mb-4">
        <.button variant="primary" patch={~p"/tags/new"}>
          <.icon name="hero-plus" class="size-4" /> New Tag
        </.button>
      </div>

      <%!-- Tags list --%>
      <ul id="tags" phx-update="stream" class="space-y-3">
        <li
          id="tags-empty"
          role="status"
          class="hidden only:block text-center py-6 text-base-content/50"
        >
          No tags yet.
        </li>
        <li
          :for={{id, tag} <- @streams.tags}
          id={id}
          class="flex flex-col gap-3 rounded-lg bg-base-200 p-4 sm:flex-row sm:items-center sm:justify-between"
        >
          <div>
            <span class="font-medium">{tag.name}</span>
            <span class="text-sm text-base-content/60 ml-2">
              {tag.expires_in_days} days
            </span>
          </div>
          <div class="flex gap-1">
            <.button
              patch={~p"/tags/#{tag.id}/edit"}
              variant="ghost"
              class="btn-sm btn-circle"
              aria-label={"Edit tag #{tag.name}"}
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <.button
              variant="ghost"
              class="btn-sm btn-circle hover:text-error cursor-pointer"
              phx-click="delete"
              phx-target={@myself}
              phx-value-id={tag.id}
              aria-label={"Delete tag #{tag.name}"}
              data-confirm="Are you sure? Links tagged with this tag will lose the tag."
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    scope = assigns.current_scope

    socket =
      socket
      |> assign(:current_scope, scope)
      |> assign(:action, assigns.action)
      |> apply_action(assigns.action, assigns)
      |> stream(:tags, Links.list_tags(scope), reset: true)

    {:ok, socket}
  end

  defp apply_action(socket, :manage_tags, _assigns) do
    assign(socket, :form, nil)
  end

  defp apply_action(socket, :new_tag, _assigns) do
    tag = %Liminal.Links.Tag{}

    socket
    |> assign(:tag, tag)
    |> assign(:form, to_form(Links.change_tag(tag)))
  end

  defp apply_action(socket, :edit_tag, %{tag_id: id}) do
    tag = Links.get_tag!(socket.assigns.current_scope, id)

    socket
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
    save_tag(socket, socket.assigns.action, tag_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    tag = Links.get_tag!(scope, id)
    {:ok, _} = Links.delete_tag(scope, tag)

    notify_parent(:tags_changed)

    {:noreply, stream_delete(socket, :tags, tag)}
  end

  defp save_tag(socket, :new_tag, tag_params) do
    scope = socket.assigns.current_scope

    case Links.create_tag(scope, tag_params) do
      {:ok, tag} ->
        notify_parent(:tags_changed)

        {:noreply,
         socket
         |> put_flash(:info, "Tag created")
         |> stream_insert(:tags, tag)
         |> push_patch(to: ~p"/tags")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_tag(socket, :edit_tag, tag_params) do
    scope = socket.assigns.current_scope

    case Links.update_tag(scope, socket.assigns.tag, tag_params) do
      {:ok, tag} ->
        notify_parent(:tags_changed)

        {:noreply,
         socket
         |> put_flash(:info, "Tag updated")
         |> stream_insert(:tags, tag)
         |> push_patch(to: ~p"/tags")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
