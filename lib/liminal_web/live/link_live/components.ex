defmodule LiminalWeb.LinkLive.Components do
  use LiminalWeb, :html

  alias LiminalWeb.LinkLive.{
    LinkCard,
    Modals,
    NewLinkForm,
    ToolbarComponents
  }

  def index(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:links}>
      <ToolbarComponents.toolbar {assigns} />

      <div id="link-shortcuts" phx-hook="LinkShortcuts" />

      <%!-- Links (masonry) --%>
      <div
        id="masonry"
        phx-hook="Masonry"
        class="relative"
      >
        <NewLinkForm.card {assigns} />
        <LinkCard.stream {assigns} />
      </div>

      <Modals.modals {assigns} />
    </Layouts.app>
    """
  end
end
