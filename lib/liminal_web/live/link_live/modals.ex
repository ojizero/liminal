defmodule LiminalWeb.LinkLive.Modals do
  @moduledoc false

  use LiminalWeb, :html

  import LiminalWeb.LinkLive.FormHandlers, only: [duplicate_pending_tags: 2]

  def modals(assigns) do
    ~H"""
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
    """
  end
end
