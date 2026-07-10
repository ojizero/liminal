defmodule LiminalWeb.StatsComponents do
  @moduledoc false
  use Phoenix.Component

  import LiminalWeb.CoreComponents

  attr :stats, :map, required: true
  attr :comprehensive, :boolean, default: false

  def stats_grid(assigns) do
    ~H"""
    <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <.stat_card
        id="stat-total-links"
        label="Saved links"
        value={@stats.total_links}
        icon="hero-link"
      />
      <.stat_card
        id="stat-unviewed"
        label="Unviewed"
        value={@stats.unviewed_links}
        icon="hero-eye-slash"
      />
      <.stat_card
        id="stat-viewed"
        label="Viewed"
        value={@stats.viewed_links}
        icon="hero-eye"
      />
      <.stat_card
        id="stat-expiring-soon"
        label="Expiring soon"
        value={@stats.expiring_soon}
        icon="hero-clock"
        hint="Within 48 hours"
      />
      <.stat_card
        id="stat-about-to-expire"
        label="About to expire"
        value={@stats.about_to_expire}
        icon="hero-calendar-days"
        hint="Within 7 days"
      />
      <.stat_card
        :if={@comprehensive}
        id="stat-index-pending"
        label="Index pending"
        value={@stats.index_pending}
        icon="hero-arrow-path"
      />
      <.stat_card
        :if={@comprehensive}
        id="stat-index-gave-up"
        label="Index gave up"
        value={@stats.index_gave_up}
        icon="hero-exclamation-triangle"
      />
      <.stat_card
        :if={!@comprehensive}
        id="stat-index-failed"
        label="Index failed"
        value={@stats.index_failed}
        icon="hero-exclamation-triangle"
      />
      <.stat_card
        :if={@comprehensive}
        id="stat-total-users"
        label="Users"
        value={@stats.total_users}
        icon="hero-users"
      />
    </div>

    <div :if={@stats.top_domains != []} id="stat-top-domains" class="mt-4">
      <h3 class="text-sm font-medium text-base-content/70 mb-2">Most bookmarked sites</h3>
      <ul class="space-y-1">
        <li
          :for={{domain, idx} <- Enum.with_index(@stats.top_domains, 1)}
          id={"stat-domain-#{idx}"}
          class="flex items-center justify-between gap-3 rounded-lg bg-base-200 px-3 py-2 text-sm"
        >
          <span class="truncate font-medium">{domain.host}</span>
          <span class="badge badge-ghost badge-sm shrink-0">{domain.count}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :hint, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-lg bg-base-200 p-4">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0">
          <p class="text-sm text-base-content/60">{@label}</p>
          <p class="text-2xl font-semibold tabular-nums">{@value}</p>
          <p :if={@hint} class="text-xs text-base-content/50 mt-1">{@hint}</p>
        </div>
        <.icon name={@icon} class="size-5 shrink-0 text-base-content/40" />
      </div>
    </div>
    """
  end
end
