defmodule LiminalWeb.Admin.DashboardLive do
  use LiminalWeb, :live_view

  import LiminalWeb.ReindexComponents
  import LiminalWeb.StatsComponents

  alias Liminal.Links
  alias LiminalWeb.ReindexHandlers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:admin}>
      <div id="admin-dashboard" class="space-y-8">
        <div class="space-y-2">
          <.header>
            Admin
            <:subtitle>Monitor the instance and manage shared maintenance tasks.</:subtitle>
          </.header>
          <Layouts.admin_nav active={:dashboard} />
        </div>

        <section id="admin-stats" aria-labelledby="admin-stats-heading" class="space-y-4">
          <.header id="admin-stats-heading" level={2}>
            Instance stats
            <:subtitle>An overview of links, users, and indexing health.</:subtitle>
          </.header>
          <.stats_grid stats={@stats} comprehensive />
        </section>

        <.panel>
          <.reindex_panel
            id="admin-reindex"
            reindex={@reindex}
            current_scope={@current_scope}
            description="Re-fetch metadata asynchronously for the whole instance. Only one reindex job can run at a time."
            failed_confirm="Reindex all links with failed indexing on this instance? This runs in the background."
            all_confirm="Reindex every link on the instance? Existing metadata will be cleared first."
          />
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Liminal.PubSub, Links.Reindex.pubsub_topic())
    end

    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:stats, Links.instance_stats(socket.assigns.current_scope))
     |> assign(:reindex, Links.reindex_status())}
  end

  @impl true
  def handle_event("start_reindex", %{"mode" => mode}, socket) do
    ReindexHandlers.handle_start_reindex(socket, &Links.start_instance_reindex/2, mode)
  end

  @impl true
  def handle_event("cancel_reindex", _params, socket) do
    ReindexHandlers.handle_cancel_reindex(socket)
  end

  @impl true
  def handle_info({:reindex_progress, reindex}, socket) do
    {:noreply, assign(socket, :reindex, reindex)}
  end
end
