defmodule LiminalWeb.CategoryLive.Index do
  use LiminalWeb, :live_view

  alias Liminal.Links

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Categories
        <:actions>
          <.button navigate={~p"/"}>Back to Links</.button>
          <.button variant="primary" patch={~p"/categories/new"}>
            <.icon name="hero-plus" class="size-4" /> New Category
          </.button>
        </:actions>
      </.header>

      <%!-- Inline form for new/edit --%>
      <div :if={@live_action in [:new, :edit]} class="mb-6 p-4 bg-base-200 rounded-lg">
        <.form for={@form} id="category-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:expires_in_days]} type="number" label="Expires in (days)" />
          <div class="flex gap-2 mt-2">
            <.button variant="primary" phx-disable-with="Saving...">Save</.button>
            <.button patch={~p"/categories"}>Cancel</.button>
          </div>
        </.form>
      </div>

      <%!-- Categories stream --%>
      <ul id="categories" phx-update="stream" class="space-y-3">
        <li id="categories-empty" class="hidden only:block text-center py-8 text-base-content/50">
          No categories yet. Create one above!
        </li>
        <li
          :for={{id, category} <- @streams.categories}
          id={id}
          class="p-4 bg-base-200 rounded-lg flex items-center justify-between group"
        >
          <div>
            <span class="font-medium">{category.name}</span>
            <span class="text-sm text-base-content/60 ml-2">
              {category.expires_in_days} days
            </span>
          </div>
          <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <.button
              patch={~p"/categories/#{category.id}/edit"}
              class="btn btn-ghost btn-sm btn-circle"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <button
              phx-click="delete"
              phx-value-id={category.id}
              data-confirm="Are you sure? Links tagged with this category will lose the tag."
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
    categories = Links.list_categories(scope)

    {:ok, stream(socket, :categories, categories)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Categories")
    |> assign(:category, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    category = %Liminal.Links.Category{}

    socket
    |> assign(:page_title, "New Category")
    |> assign(:category, category)
    |> assign(:form, to_form(Links.change_category(category)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    category = Links.get_category!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Category")
    |> assign(:category, category)
    |> assign(:form, to_form(Links.change_category(category)))
  end

  @impl true
  def handle_event("validate", %{"category" => category_params}, socket) do
    changeset =
      socket.assigns.category
      |> Links.change_category(category_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"category" => category_params}, socket) do
    save_category(socket, socket.assigns.live_action, category_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    category = Links.get_category!(scope, id)
    {:ok, _} = Links.delete_category(scope, category)

    {:noreply, stream_delete(socket, :categories, category)}
  end

  defp save_category(socket, :new, category_params) do
    scope = socket.assigns.current_scope

    case Links.create_category(scope, category_params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created")
         |> stream_insert(:categories, category)
         |> push_patch(to: ~p"/categories")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_category(socket, :edit, category_params) do
    scope = socket.assigns.current_scope

    case Links.update_category(scope, socket.assigns.category, category_params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated")
         |> stream_insert(:categories, category)
         |> push_patch(to: ~p"/categories")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
