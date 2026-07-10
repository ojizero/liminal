defmodule LiminalWeb.ReindexComponents do
  @moduledoc false
  use Phoenix.Component

  import LiminalWeb.CoreComponents

  alias Liminal.Links

  attr :id, :string, default: "reindex"
  attr :reindex, :map, required: true
  attr :current_scope, :map, required: true
  attr :heading, :string, default: "Reindex links"
  attr :description, :string, required: true
  attr :failed_confirm, :string, required: true
  attr :all_confirm, :string, required: true

  def reindex_panel(assigns) do
    assigns =
      assign(
        assigns,
        :cancellable?,
        Links.can_cancel_reindex?(assigns.current_scope, assigns.reindex)
      )

    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-heading"} class="space-y-4">
      <.header id={"#{@id}-heading"} level={2}>
        {@heading}
        <:subtitle>{@description}</:subtitle>
      </.header>

      <div
        id={"#{@id}-status"}
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
              id={"#{@id}-progress"}
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
          id={"#{@id}-failed-btn"}
          variant="primary"
          phx-click="start_reindex"
          phx-value-mode="failed"
          phx-disable-with="Starting…"
          disabled={@reindex.active}
          data-confirm={@failed_confirm}
        >
          <.icon name="hero-arrow-path" class="size-4" /> Reindex failed
        </.button>
        <.button
          id={"#{@id}-all-btn"}
          variant="soft"
          phx-click="start_reindex"
          phx-value-mode="all"
          phx-disable-with="Starting…"
          disabled={@reindex.active}
          data-confirm={@all_confirm}
        >
          <.icon name="hero-arrow-path-rounded-square" class="size-4" /> Reindex all
        </.button>
        <.button
          id={"#{@id}-cancel-btn"}
          variant="ghost"
          phx-click="cancel_reindex"
          phx-disable-with="Cancelling…"
          disabled={!@reindex.active || !@cancellable?}
        >
          Cancel job
        </.button>
      </div>
    </section>
    """
  end

  def reindex_scope_label({:instance, :all}, _), do: "Instance · all links"
  def reindex_scope_label({:instance, :failed}, _), do: "Instance · failed only"
  def reindex_scope_label({:user, _user_id, :all}, _), do: "Your links · all"
  def reindex_scope_label({:user, _user_id, :failed}, _), do: "Your links · failed only"
  def reindex_scope_label({:link, _link_id}, _), do: "Single link"
  def reindex_scope_label(nil, nil), do: "—"
  def reindex_scope_label(_scope, mode), do: reindex_mode_label(mode)

  def reindex_mode_label(:all), do: "All links"
  def reindex_mode_label(:failed), do: "Failed only"
  def reindex_mode_label(nil), do: "—"

  defp reindex_status_label(%{active: true}), do: "Running"
  defp reindex_status_label(%{active: false}), do: "Idle"

  defp reindex_outcome_label(:completed), do: "completed"
  defp reindex_outcome_label(:cancelled), do: "cancelled"
  defp reindex_outcome_label(_), do: "finished"
end
