defmodule LiminalWeb.Components.Modal do
  @moduledoc """
  DaisyUI `<dialog>` modal — no custom JavaScript.

  - **Open:** LiveView renders the dialog when `show` is true (`live_action` + `patch`).
  - **Visible:** `open` + daisyUI `modal` classes (daisy styles `dialog[open]`).
  - **Close:** `on_cancel` (`JS.patch/1`) via backdrop click, Escape, or the footer Close button.

  See [responsive](https://daisyui.com/components/modal/#responsive) and
  [click-outside](https://daisyui.com/components/modal/#dialog-modal-closes-when-clicked-outside).
  """
  use Phoenix.Component
  use Gettext, backend: LiminalWeb.Gettext

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :closeable, :boolean, default: true
  attr :show_close, :boolean, default: true, doc: "footer Close button in modal-action (daisyUI default)"
  attr :close_label, :string, default: "Close"
  attr :box_class, :string, default: nil, doc: "extra modal-box classes (prefer sm:max-w-* so bottom sheet stays full width)"

  slot :inner_block, required: true
  slot :title

  def modal(assigns) do
    box_class =
      ["modal-box", assigns[:box_class]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    assigns = assign(assigns, :box_class, box_class)

    ~H"""
    <dialog
      :if={@show}
      id={@id}
      open
      class="modal modal-bottom sm:modal-middle"
      phx-window-keydown={@closeable && @on_cancel}
      phx-key="Escape"
    >
      <div class={@box_class}>
        <h3 :if={@title != []} class="text-lg font-bold">
          {render_slot(@title)}
        </h3>

        <div class={@title != [] && "py-4"}>
          {render_slot(@inner_block)}
        </div>

        <div :if={@closeable && @show_close} class="modal-action">
          <button type="button" class="btn" phx-click={@on_cancel}>
            {@close_label}
          </button>
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
