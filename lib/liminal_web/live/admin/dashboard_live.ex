defmodule LiminalWeb.Admin.DashboardLive do
  use LiminalWeb, :live_view

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

      <section id="admin-reindex" aria-labelledby="admin-reindex-heading" class="space-y-4">
        <h2 id="admin-reindex-heading" class="text-lg font-semibold">Mass reindex</h2>
        <p class="text-sm text-base-content/70">
          Re-fetch metadata for links asynchronously. Jobs are rate-limited to avoid overloading the instance.
        </p>

        <div
          id="reindex-status"
          class={[
            "rounded-lg border p-4",
            @reindex.status == :running && "border-primary/30 bg-primary/5",
            @reindex.status == :idle && "border-base-300 bg-base-200/50"
          ]}
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-sm font-medium">Status</span>
            <span class={[
              "badge badge-sm",
              if(@reindex.status == :running, do: "badge-primary", else: "badge-ghost")
            ]}>
              {reindex_status_label(@reindex)}
            </span>
            <%= if @reindex.mode do %>
              <span class="text-sm text-base-content/60">
                Mode: {reindex_mode_label(@reindex.mode)}
              </span>
            <% end %>
          </div>

          <%= if @reindex.status == :running do %>
            <div class="mt-3 space-y-2">
              <progress
                id="reindex-progress"
                class="progress progress-primary w-full"
                value={@reindex.processed}
                max={max(@reindex.total, 1)}
              >
              </progress>
              <p class="text-sm text-base-content/70">
                {@reindex.processed} of {@reindex.total} processed
                <span :if={@reindex.remaining > 0}>
                  ({@reindex.remaining} remaining)
                </span>
              </p>
            </div>
          <% end %>

          <%= if @reindex.last_job && @reindex.status == :idle do %>
            <p class="mt-2 text-sm text-base-content/60">
              Last job: {reindex_mode_label(@reindex.last_job.mode)} — {@reindex.last_job.processed} of {@reindex.last_job.total} processed
            </p>
          <% end %>
        </div>

        <div class="flex flex-wrap gap-2">
          <.button
            id="reindex-failed-btn"
            variant="primary"
            phx-click="start_reindex"
            phx-value-mode="failed"
            phx-disable-with="Starting…"
            disabled={@reindex.status == :running}
            data-confirm="Reindex all links with failed indexing? This runs in the background."
          >
            <.icon name="hero-arrow-path" class="size-4" /> Reindex failed
          </.button>
          <.button
            id="reindex-all-btn"
            variant="soft"
            phx-click="start_reindex"
            phx-value-mode="all"
            phx-disable-with="Starting…"
            disabled={@reindex.status == :running}
            data-confirm="Reindex every link on the instance? Existing metadata will be cleared first."
          >
            <.icon name="hero-arrow-path-rounded-square" class="size-4" /> Reindex all
          </.button>
          <.button
            id="reindex-cancel-btn"
            variant="ghost"
            phx-click="cancel_reindex"
            phx-disable-with="Cancelling…"
            disabled={@reindex.status != :running}
          >
            Cancel
          </.button>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Liminal.PubSub, Links.MassReindexer.pubsub_topic())
    end

    {:ok,
     socket
     |> assign(:stats, Links.instance_stats(scope))
     |> assign(:reindex, Links.mass_reindex_status(scope))}
  end

  @impl true
  def handle_event("start_reindex", %{"mode" => mode}, socket) do
    scope = socket.assigns.current_scope
    mode = String.to_existing_atom(mode)

    case Links.start_mass_reindex(scope, mode) do
      {:ok, reindex} ->
        {:noreply,
         socket
         |> assign(:reindex, reindex)
         |> put_flash(:info, "Mass reindex started (#{reindex_mode_label(mode)}).")}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "A reindex job is already running.")}
    end
  end

  @impl true
  def handle_event("cancel_reindex", _params, socket) do
    scope = socket.assigns.current_scope
    :ok = Links.cancel_mass_reindex(scope)

    {:noreply,
     socket
     |> assign(:reindex, Links.mass_reindex_status(scope))
     |> put_flash(:info, "Mass reindex cancelled.")}
  end

  @impl true
  def handle_info({:reindex_progress, reindex}, socket) do
    {:noreply, assign(socket, :reindex, reindex)}
  end

  defp reindex_status_label(%{status: :running}), do: "Running"
  defp reindex_status_label(%{status: :idle}), do: "Idle"

  defp reindex_mode_label(:all), do: "All links"
  defp reindex_mode_label(:failed), do: "Failed only"
  defp reindex_mode_label(nil), do: "—"
end
