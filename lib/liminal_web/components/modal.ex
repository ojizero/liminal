defmodule LiminalWeb.Components.Modal do
  @moduledoc """
  DaisyUI `<dialog>` modal — no custom JavaScript.

  - **Open:** LiveView renders the dialog when `show` is true (`live_action` + `patch`).
  - **Visible:** `open` + daisyUI `modal` classes (daisy styles `dialog[open]`).
  - **Close:** `on_cancel` via corner ✕, backdrop click, or Escape.
  - **Mobile:** bottom sheet (`modal-bottom sm:modal-middle`) for touch-friendly reach.
  - **Overflow:** the title/✕ header is pinned and only the body scrolls, so the ✕
    stays reachable when content is taller than the viewport. Escape is unavailable
    on touch devices, which makes the ✕ the primary dismiss control there.

  See [responsive](https://daisyui.com/components/modal/#responsive),
  [click-outside](https://daisyui.com/components/modal/#dialog-modal-closes-when-clicked-outside),
  and [close button at corner](https://daisyui.com/components/modal/#dialog-modal-with-a-close-button-at-corner).
  """
  use Phoenix.Component
  use Gettext, backend: LiminalWeb.Gettext

  import LiminalWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :closeable, :boolean, default: true

  attr :show_close, :boolean,
    default: true,
    doc: "corner ✕ close button (daisyUI dialog modal with close button at corner)"

  attr :box_class, :string,
    default: nil,
    doc: "extra modal-box classes (prefer sm:max-w-* so bottom sheet stays full width)"

  slot :inner_block, required: true
  slot :title

  def modal(assigns) do
    box_class =
      [
        "modal-box",
        # daisyUI caps the box with `vh`; `dvh` keeps mobile browser chrome out of the way
        "flex max-h-[calc(100dvh-5rem)] flex-col overflow-hidden",
        assigns[:box_class]
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    assigns =
      assigns
      |> assign(:box_class, box_class)
      |> assign(:close?, assigns.closeable && assigns.show_close)

    ~H"""
    <dialog
      :if={@show}
      id={@id}
      open
      aria-modal="true"
      aria-labelledby={@title != [] && "#{@id}-title"}
      class="modal modal-bottom sm:modal-middle"
      phx-window-keydown={@closeable && @on_cancel}
      phx-key="Escape"
    >
      <div class={@box_class}>
        <div
          :if={@title != [] || @close?}
          id={"#{@id}-header"}
          class={["flex shrink-0 items-start justify-between gap-4", @title != [] && "pb-4"]}
        >
          <h2 :if={@title != []} id={"#{@id}-title"} class="text-lg font-bold">
            {render_slot(@title)}
          </h2>

          <button
            :if={@close?}
            type="button"
            id={"#{@id}-close"}
            class="btn btn-sm btn-circle btn-ghost -mr-2 -mt-2 ml-auto"
            phx-click={@on_cancel}
            aria-label={gettext("close")}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div id={"#{@id}-body"} class="min-h-0 flex-1 overflow-y-auto overscroll-contain">
          {render_slot(@inner_block)}
        </div>
      </div>

      <form :if={@closeable} class="modal-backdrop" phx-click={@on_cancel}>
        <button type="button" class="size-full cursor-default" aria-label={gettext("close")}>
          {gettext("close")}
        </button>
      </form>
    </dialog>
    """
  end
end
