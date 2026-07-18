defmodule LiminalWeb.Components.Modal do
  @moduledoc """
  DaisyUI `<dialog>` modal — no custom JavaScript.

  - **Open:** LiveView renders the dialog when `show` is true (`live_action` + `patch`).
  - **Visible:** `open` + daisyUI `modal` classes (daisy styles `dialog[open]`).
  - **Close:** `on_cancel` via corner ✕, backdrop click, or Escape.
  - **Mobile:** bottom sheet (`modal-bottom sm:modal-middle`) for touch-friendly reach.

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
      ["modal-box", "relative", assigns[:box_class]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    assigns = assign(assigns, :box_class, box_class)

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
        <button
          :if={@closeable && @show_close}
          type="button"
          id={"#{@id}-close"}
          class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
          phx-click={@on_cancel}
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>

        <h2 :if={@title != []} id={"#{@id}-title"} class="text-lg font-bold pr-10">
          {render_slot(@title)}
        </h2>

        <div class={@title != [] && "py-4"}>
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
