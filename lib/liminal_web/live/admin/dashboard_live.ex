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
        <h2 id="admin-reindex-heading" class="text-lg font-semibold">Reindex links</h2>
        <p class="text-sm text-base-content/70">
          Re-fetch metadata asynchronously. Only one reindex job can run at a time; new jobs are blocked until the active job finishes or is cancelled.
        </p>

        <div
          id="reindex-status"
          class={[
            "rounded-lg border p-4",
            @reindex.active && "border-primary/30 bg-primary/5",
            !@reindex.active && "border-base-300 bg-base-200/50"
          ]}
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-sm font-medium">Job status</span>
            <span class={[
              "badge badge-sm",
              if(@reindex.active, do: "badge-primary", else: "badge-ghost")
            ]}>
              {reindex_status_label(@reindex)}
            </span>
            <%= if @reindex.active do %>
              <span class="text-sm text-base-content/60">
                Scope: {reindex_scope_label(@reindex.scope, @reindex.mode)}
              </span>
            <% end %>
          </div>

          <%= if @reindex.active do %>
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

          <%= if @reindex.last_job && !@reindex.active do %>
            <p class="mt-2 text-sm text-base-content/60">
              Last job: {reindex_scope_label(@reindex.last_job.scope, @reindex.last_job.mode)} — {@reindex.last_job.processed} of {@reindex.last_job.total} processed
              ({reindex_outcome_label(@reindex.last_job.outcome)})
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
            disabled={@reindex.active}
            data-confirm="Reindex all links with failed indexing on this instance? This runs in the background."
          >
            <.icon name="hero-arrow-path" class="size-4" /> Reindex failed
          </.button>
          <.button
            id="reindex-all-btn"
            variant="soft"
            phx-click="start_reindex"
            phx-value-mode="all"
            phx-disable-with="Starting…"
            disabled={@reindex.active}
            data-confirm="Reindex every link on the instance? Existing metadata will be cleared first."
          >
            <.icon name="hero-arrow-path-rounded-square" class="size-4" /> Reindex all
          </.button>
          <.button
            id="reindex-cancel-btn"
            variant="ghost"
            phx-click="cancel_reindex"
            phx-disable-with="Cancelling…"
            disabled={!@reindex.active}
          >
            Cancel job
          </.button>
        </div>
      </section>
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

  defp reindex_status_label(%{active: true}), do: "Running"
  defp reindex_status_label(%{active: false}), do: "Idle"

  defp reindex_scope_label({:instance, :all}, _), do: "Instance · all links"
  defp reindex_scope_label({:instance, :failed}, _), do: "Instance · failed only"
  defp reindex_scope_label({:user, _user_id, :all}, _), do: "User · all links"
  defp reindex_scope_label({:user, _user_id, :failed}, _), do: "User · failed only"
  defp reindex_scope_label({:link, _link_id}, _), do: "Single link"
  defp reindex_scope_label(nil, nil), do: "—"
  defp reindex_scope_label(_scope, mode), do: reindex_mode_label(mode)

  defp reindex_mode_label(:all), do: "All links"
  defp reindex_mode_label(:failed), do: "Failed only"
  defp reindex_mode_label(nil), do: "—"

  defp reindex_outcome_label(:completed), do: "completed"
  defp reindex_outcome_label(:cancelled), do: "cancelled"
  defp reindex_outcome_label(_), do: "finished"
end
