defmodule LiminalWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: LiminalWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"

  attr :autoclose, :boolean,
    default: true,
    doc: "whether to auto-dismiss the flash after a timeout"

  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"
  slot :actions, doc: "optional actions rendered below the message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-hook=".FlashAutoClose"
      data-timeout={@autoclose && "5000"}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div class="min-w-0">
          <p :if={@title} class="font-semibold">{@title}</p>
          <div>{msg}</div>
          {render_slot(@actions)}
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".FlashAutoClose">
      export default {
        mounted() {
          const timeout = parseInt(this.el.dataset.timeout, 10)
          if (!timeout) return
          this.timer = setTimeout(() => this.el.click(), timeout)
        },
        destroyed() {
          clearTimeout(this.timer)
        }
      }
    </script>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"} variant="ghost">Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any, default: nil
  attr :variant, :string, values: ~w(primary soft ghost), default: "ghost"
  slot :inner_block, required: true

  @button_variants %{
    "primary" => "btn-primary",
    "soft" => "btn-primary btn-soft",
    "ghost" => "btn-ghost"
  }

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(
        assigns,
        :computed_class,
        ["btn", Map.fetch!(@button_variants, assigns.variant), assigns[:class]]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
      )

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@computed_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@computed_class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"
  attr :fieldset_class, :any, default: nil, doc: "extra classes on the fieldset wrapper"

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled enterkeyhint form inputmode list max maxlength min
                minlength multiple pattern placeholder readonly required rows size step aria-controls
                aria-describedby aria-invalid aria-keyshortcuts aria-label aria-labelledby)

  slot :suffix, doc: "optional content overlaid on the input (e.g. keyboard shortcut hints)"

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> assign_input_aria()
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assigns
      |> assign_new(:checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)
      |> assign_input_aria()

    ~H"""
    <div class={["fieldset mb-2", @fieldset_class]}>
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={[
              @class || "checkbox checkbox-sm",
              @has_errors && "validator"
            ]}
            aria-invalid={@aria_invalid}
            aria-describedby={@aria_describedby}
            {@rest}
          />{@label}
        </span>
      </label>
      <.field_errors errors={@errors} id={@error_id} />
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    assigns = assign_input_aria(assigns)

    ~H"""
    <div class={["fieldset mb-2", @fieldset_class]}>
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class || "w-full select",
            @has_errors && (@error_class || "select-error"),
            @has_errors && "validator"
          ]}
          aria-invalid={@aria_invalid}
          aria-describedby={@aria_describedby}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.field_errors errors={@errors} id={@error_id} />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    assigns = assign_input_aria(assigns)

    ~H"""
    <div class={["fieldset mb-2", @fieldset_class]}>
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <div class={[@suffix != [] && "relative"]}>
          <textarea
            id={@id}
            name={@name}
            class={[
              @class || "w-full textarea",
              @has_errors && (@error_class || "textarea-error"),
              @has_errors && "validator"
            ]}
            aria-invalid={@aria_invalid}
            aria-describedby={@aria_describedby}
            {@rest}
          >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
          {render_slot(@suffix)}
        </div>
      </label>
      <.field_errors errors={@errors} id={@error_id} />
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    assigns = assign_input_aria(assigns)

    ~H"""
    <div class={["fieldset mb-2", @fieldset_class]}>
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <div class={[@suffix != [] && "relative"]}>
          <input
            type={@type}
            name={@name}
            id={@id}
            value={Phoenix.HTML.Form.normalize_value(@type, @value)}
            class={[
              "w-full input",
              @class,
              @has_errors && (@error_class || "input-error"),
              @has_errors && "validator"
            ]}
            aria-invalid={@aria_invalid}
            aria-describedby={@aria_describedby}
            {@rest}
          />
          {render_slot(@suffix)}
        </div>
      </label>
      <.field_errors errors={@errors} id={@error_id} />
    </div>
    """
  end

  defp assign_input_aria(assigns) do
    has_errors = assigns.errors != []
    error_id = if has_errors, do: "#{assigns.id}-error", else: nil

    assigns
    |> assign(:has_errors, has_errors)
    |> assign(:error_id, error_id)
    |> assign(:aria_invalid, has_errors)
    |> assign(:aria_describedby, error_id)
  end

  attr :errors, :list, required: true
  attr :id, :string, default: nil

  defp field_errors(assigns) do
    ~H"""
    <div :if={@errors != []} id={@id} role="alert" class="space-y-1">
      <p
        :for={msg <- @errors}
        class="mt-1.5 flex gap-2 items-center text-sm text-error validator-hint"
      >
        <.icon name="hero-exclamation-circle" class="size-5" aria_hidden={true} />
        {msg}
      </p>
    </div>
    """
  end

  @doc """
  Renders a header with title.

  Use `level={2}` for section headings when the page already has an `h1`.
  """
  attr :id, :string, default: nil
  attr :level, :integer, default: 1, values: [1, 2]
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex items-center justify-between gap-3 sm:gap-6",
      "pb-4"
    ]}>
      <div class="min-w-0">
        <%= if @level == 1 do %>
          <h1 id={@id} class="text-lg font-semibold leading-8">
            {render_slot(@inner_block)}
          </h1>
        <% else %>
          <h2 id={@id} class="text-lg font-semibold leading-8">
            {render_slot(@inner_block)}
          </h2>
        <% end %>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="flex shrink-0 flex-wrap justify-end gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  Renders a consistent surface for grouped page content.
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "rounded-xl border border-base-300 bg-base-200/70 p-5 shadow-sm sm:p-6",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  Wraps content in a [daisyUI tooltip](https://daisyui.com/components/tooltip/) trigger.

  `data-tip` is hover-only. Put `aria-label` on the focusable child inside the slot
  so screen readers get an accessible name.

  ## Examples

      <.with_tooltip tip="Edit">
        <button aria-label="Edit link" class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-pencil-square" />
        </button>
      </.with_tooltip>

      <.with_tooltip
        id="paste-hint"
        tip="Paste a copied URL from your clipboard."
        placement={:top}
        class="cursor-default inline-flex items-center gap-1.5"
      >
        <span class="text-xs text-base-content/45">Paste anywhere</span>
      </.with_tooltip>
  """
  attr :tip, :string, required: true, doc: "tooltip text shown on hover (data-tip)"
  attr :placement, :atom, default: :top, values: [:top, :bottom, :left, :right]
  attr :id, :string, default: nil
  attr :class, :any, default: nil, doc: "extra classes on the tooltip wrapper"
  attr :rest, :global, doc: "additional HTML attributes on the tooltip wrapper"
  slot :inner_block, required: true

  @tooltip_placements %{
    top: "tooltip-top",
    bottom: "tooltip-bottom",
    left: "tooltip-left",
    right: "tooltip-right"
  }

  def with_tooltip(assigns) do
    assigns =
      assign(assigns, :placement_class, Map.fetch!(@tooltip_placements, assigns.placement))

    ~H"""
    <span
      id={@id}
      class={["tooltip", @placement_class, @class]}
      data-tip={@tip}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"
  attr :aria_hidden, :boolean, default: true

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} aria-hidden={@aria_hidden} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @shortcut_kbd_class "kbd kbd-xs min-h-0 h-5 px-1.5 text-base-content/45 border-base-content/15 bg-base-100/80"

  @doc """
  Renders a keyboard shortcut hint.

  On macOS, modifier keys use U+2303 (⌃) and U+21E7 (⇧).
  On other platforms, `label` is shown as plain text.
  """
  attr :platform, :atom, default: nil
  attr :mod, :atom, default: nil
  attr :label, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  def shortcut_kbd(assigns) do
    symbol? = assigns.platform == :mac and assigns.mod in [:control, :shift]

    assigns =
      assigns
      |> assign(:symbol?, symbol?)
      |> assign(:class, assigns[:class] || @shortcut_kbd_class)
      |> assign(:aria_label, mod_aria_label(assigns.mod))

    ~H"""
    <kbd
      class={[@class, @symbol? && "kbd-mod-symbol"]}
      data-shortcut-mod={@mod}
      aria-label={@aria_label}
      {@rest}
    >
      <%= cond do %>
        <% @symbol? -> %>
          {mac_mod_symbol(@mod)}
        <% true -> %>
          {@label}
      <% end %>
    </kbd>
    """
  end

  defp mod_aria_label(:control), do: "Control"
  defp mod_aria_label(:shift), do: "Shift"
  defp mod_aria_label(_), do: nil

  defp mac_mod_symbol(:control), do: <<0x2303::utf8>>
  defp mac_mod_symbol(:shift), do: <<0x21E7::utf8>>

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(LiminalWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(LiminalWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
