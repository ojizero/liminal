defmodule LiminalWeb.Admin.DashboardLive do
  use LiminalWeb, :live_view

  import LiminalWeb.ReindexComponents
  import LiminalWeb.StatsComponents

  alias Liminal.Links

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={:admin}>
      <.header>
        Admin Dashboard
        <:actions>
          <.link navigate={~p"/admin/users"} class="btn btn-soft btn-sm">
            <.icon name="hero-users" class="size-4" /> Manage Users
          </.link>
        </:actions>
      </.header>

      <section id="admin-stats" aria-labelledby="admin-stats-heading" class="space-y-4">
        <h2 id="admin-stats-heading" class="text-lg font-semibold">Instance stats</h2>
        <.stats_grid stats={@stats} comprehensive />
      </section>

      <.reindex_panel
        id="admin-reindex"
        reindex={@reindex}
        current_scope={@current_scope}
        description="Re-fetch metadata asynchronously for the whole instance. Only one reindex job can run at a time."
        failed_confirm="Reindex all links with failed indexing on this instance? This runs in the background."
        all_confirm="Reindex every link on the instance? Existing metadata will be cleared first."
      />
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
     |> assign(:stats, Links.instance_stats(socket.assigns.current_scope))
     |> assign(:reindex, Links.reindex_status())}
  end

  @impl true
  def handle_event("start_reindex", %{"mode" => mode}, socket) do
    scope = socket.assigns.current_scope
    mode = String.to_existing_atom(mode)

    case Links.start_instance_reindex(scope, mode) do
      {:ok, reindex} ->
        message =
          if reindex.active do
            "Reindex job started (#{reindex_scope_label(reindex.scope, reindex.mode)})."
          else
            "No links matched that reindex scope."
          end

        {:noreply,
         socket
         |> assign(:reindex, reindex)
         |> put_flash(:info, message)}

      {:error, :already_running} ->
        {:noreply,
         socket
         |> assign(:reindex, Links.reindex_status())
         |> put_flash(
           :error,
           "A reindex job is already running. Cancel it or wait for it to finish."
         )}
    end
  end

  @impl true
  def handle_event("cancel_reindex", _params, socket) do
    scope = socket.assigns.current_scope

    case Links.cancel_reindex(scope) do
      :ok ->
        {:noreply,
         socket
         |> assign(:reindex, Links.reindex_status())
         |> put_flash(:info, "Reindex job cancelled.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You cannot cancel this reindex job.")}
    end
  end

  @impl true
  def handle_info({:reindex_progress, reindex}, socket) do
    {:noreply, assign(socket, :reindex, reindex)}
  end
end
