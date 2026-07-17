defmodule LiminalWeb.LinkLive.NewLinkForm do
  @moduledoc false

  use LiminalWeb, :html

  import LiminalWeb.LinkLive.Shortcuts,
    only: [
      focus_url_aria_keyshortcuts: 1,
      paste_aria_keyshortcuts: 1,
      save_note_aria_keyshortcuts: 1,
      shortcut_mod_label: 1,
      tag_toggle_aria_keyshortcuts: 1,
      tag_toggle_ctrl_label: 1,
      tag_toggle_shift_label: 1
    ]

  def card(assigns) do
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
end
