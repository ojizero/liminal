defmodule LiminalWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LiminalWeb, :html

  alias Liminal.Accounts.Scope

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :active_nav, :atom,
    default: nil,
    doc: "highlights the matching item in the user menu (:links or :admin)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a
      href="#main-content"
      class="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 btn btn-sm btn-primary"
    >
      Skip to main content
    </a>

    <header class="navbar min-h-14 gap-2 px-3 sm:px-6 lg:px-8">
      <div class="flex-1 min-w-0">
        <.link
          navigate={~p"/"}
          class="flex w-fit max-w-full items-center gap-2 text-base font-bold tracking-tight sm:text-lg"
        >
          <img src={~p"/liminal.svg"} class="size-6 shrink-0" alt="" />
          <span class="truncate">liminal</span>
        </.link>
      </div>
      <div class="flex shrink-0 items-center gap-1.5 sm:gap-3">
        <div class="origin-right scale-90 sm:scale-100">
          <.theme_toggle />
        </div>
        <%= if @current_scope do %>
          <details class="dropdown dropdown-end">
            <summary
              class="btn btn-ghost btn-sm flex max-w-[2.75rem] items-center gap-1.5 px-2 sm:max-w-none sm:px-3"
              aria-label={"Account menu for #{@current_scope.user.username}"}
            >
              <.icon name="hero-user-circle" class="size-5 shrink-0" />
              <span class="hidden truncate text-sm sm:inline max-w-[8rem]">
                {@current_scope.user.username}
              </span>
            </summary>
            <nav aria-label="Account">
              <ul
                id="user-menu"
                class="dropdown-content menu bg-base-200 rounded-box z-10 mt-2 w-52 p-2 shadow"
              >
                <li>
                  <.link
                    navigate={~p"/"}
                    class={[@active_nav == :links && "menu-active"]}
                    aria-current={@active_nav == :links && "page"}
                  >
                    <.icon name="hero-link" class="size-4" /> Links
                  </.link>
                </li>
                <%= if Scope.admin?(@current_scope) do %>
                  <li>
                    <.link
                      navigate={~p"/admin/users"}
                      class={[@active_nav == :admin && "menu-active"]}
                      aria-current={@active_nav == :admin && "page"}
                    >
                      <.icon name="hero-shield-check" class="size-4" /> Admin
                    </.link>
                  </li>
                <% end %>
                <li class="pointer-events-none my-1">
                  <hr class="border-base-content/10" />
                </li>
                <li>
                  <.link navigate={~p"/users/settings"}>
                    <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
                  </.link>
                </li>
                <li>
                  <.link
                    href={~p"/users/log-out"}
                    method="delete"
                    class="text-error hover:text-error"
                  >
                    <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Log out
                  </.link>
                </li>
              </ul>
            </nav>
          </details>
        <% end %>
      </div>
    </header>

    <main id="main-content" class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Narrow centered column for auth flows and account settings forms.
  """
  slot :inner_block, required: true

  def narrow_page(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm w-full space-y-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        autoclose={false}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        autoclose={false}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides Catppuccin Mocha/Latte theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      phx-hook=".ThemeToggle"
      role="group"
      aria-label="Color theme"
      class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full"
    >
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=latte]_&]:left-1/3 [[data-theme=mocha]_&]:left-2/3 transition-[left]" />

      <button
        type="button"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="System theme"
        aria-pressed="false"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="latte"
        aria-label="Light theme"
        aria-pressed="false"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="mocha"
        aria-label="Dark theme"
        aria-pressed="false"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ThemeToggle">
      export default {
        mounted() {
          this.syncPressed()
          this.onTheme = () => this.syncPressed()
          window.addEventListener("phx:set-theme", this.onTheme)
        },
        destroyed() {
          window.removeEventListener("phx:set-theme", this.onTheme)
        },
        syncPressed() {
          const stored = localStorage.getItem("phx:theme")
          const attr = document.documentElement.getAttribute("data-theme")
          const active = stored || (attr ? attr : "system")

          this.el.querySelectorAll("button[data-phx-theme]").forEach((button) => {
            const pressed = button.dataset.phxTheme === active
            button.setAttribute("aria-pressed", pressed ? "true" : "false")
          })
        }
      }
    </script>
    """
  end
end
