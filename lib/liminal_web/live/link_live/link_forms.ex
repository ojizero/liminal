defmodule LiminalWeb.LinkLive.LinkForms do
  import Phoenix.Component, only: [assign: 3, to_form: 1, to_form: 2]

  alias Liminal.Links
  alias LiminalWeb.LinkLive.Streaming
  alias Phoenix.LiveView

  def validate_link(socket, link_params) do
    changeset =
      socket.assigns.link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    assign(socket, :form, to_form(changeset))
  end

  def validate_edit(socket, link_params) do
    changeset =
      socket.assigns.editing_link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    assign(socket, :edit_form, to_form(changeset, as: :edit_link))
  end

  def save_link(socket, :index, link_params) do
    scope = socket.assigns.current_scope
    tag_ids = socket.assigns.selected_tag_ids

    changeset =
      socket.assigns.link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    cond do
      tag_ids == [] ->
        {:noreply, LiveView.put_flash(socket, :error, "Select at least one tag")}

      not changeset.valid? ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      true ->
        save_valid_link(socket, scope, link_params, tag_ids, changeset)
    end
  end

  def confirm_duplicate_merge(socket) do
    scope = socket.assigns.current_scope
    link = socket.assigns.duplicate_link
    tag_ids = socket.assigns.pending_tag_ids

    case Links.merge_link_tags(scope, link, tag_ids) do
      {:ok, updated_link} ->
        new_link = %Liminal.Links.Link{}

        {:noreply,
         socket
         |> LiveView.put_flash(:info, "Link updated")
         |> LiveView.stream_insert(:links, updated_link)
         |> clear_duplicate_state()
         |> assign(:link, new_link)
         |> assign(:selected_tag_ids, [])
         |> assign(:form, to_form(Links.change_link(new_link)))}

      {:error, :invalid_tags} ->
        {:noreply, LiveView.put_flash(socket, :error, "One or more selected tags are invalid")}

      {:error, :no_tags} ->
        {:noreply, LiveView.put_flash(socket, :error, "Select at least one tag")}
    end
  end

  def save_edit(socket, link_params) do
    scope = socket.assigns.current_scope

    case Links.update_link(scope, socket.assigns.editing_link, link_params) do
      {:ok, link} ->
        link = Links.get_link!(scope, link.id)

        {:noreply,
         socket
         |> LiveView.put_flash(:info, "Link updated")
         |> LiveView.stream_insert(:links, link)
         |> LiveView.push_patch(to: "/")}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: :edit_link))}
    end
  end

  def create_new_link(socket, link_params, tag_ids) do
    scope = socket.assigns.current_scope

    case Links.create_link(scope, link_params, tag_ids) do
      {:ok, link} ->
        link = Links.get_link!(scope, link.id)
        new_link = %Liminal.Links.Link{}

        {:noreply,
         socket
         |> LiveView.put_flash(:info, "Link added")
         |> Streaming.maybe_stream_insert_link(link)
         |> assign(:link, new_link)
         |> assign(:selected_tag_ids, [])
         |> assign(:form, to_form(Links.change_link(new_link)))}

      {:error, :no_tags} ->
        {:noreply, LiveView.put_flash(socket, :error, "Select at least one tag")}

      {:error, :invalid_tags} ->
        {:noreply, LiveView.put_flash(socket, :error, "One or more selected tags are invalid")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def clear_duplicate_state(socket) do
    socket
    |> assign(:duplicate_link, nil)
    |> assign(:pending_link_params, nil)
    |> assign(:pending_tag_ids, [])
  end

  def duplicate_pending_tags(tags, pending_tag_ids) do
    pending = MapSet.new(pending_tag_ids)
    Enum.filter(tags, fn tag -> tag.id in pending end)
  end

  defp save_valid_link(socket, scope, link_params, tag_ids, changeset) do
    url = Ecto.Changeset.get_field(changeset, :url)

    case Links.find_link_by_url(scope, url) do
      nil -> create_new_link(socket, link_params, tag_ids)
      existing -> show_duplicate_modal(socket, scope, existing, link_params, tag_ids, changeset)
    end
  end

  defp show_duplicate_modal(socket, scope, existing, link_params, tag_ids, changeset) do
    existing = Links.get_link!(scope, existing.id)

    {:noreply,
     socket
     |> assign(:duplicate_link, existing)
     |> assign(:pending_link_params, link_params)
     |> assign(:pending_tag_ids, tag_ids)
     |> assign(:form, to_form(changeset))}
  end
end
