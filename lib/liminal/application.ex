defmodule Liminal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_create_db()
    Liminal.AssetPaths.ensure_assets_dir!()

    children =
      [
        LiminalWeb.Telemetry,
        Liminal.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:liminal, :ecto_repos), skip: not auto_migrate?()},
        {DNSCluster, query: Application.get_env(:liminal, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Liminal.PubSub},
        {Task.Supervisor, name: Liminal.Links.IndexerTaskSupervisor},
        # Start to serve requests, typically the last entry
        LiminalWeb.Endpoint
      ] ++ janitor_children() ++ mass_reindexer_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Liminal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LiminalWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp janitor_children do
    if Application.get_env(:liminal, :start_janitor, true) do
      [Liminal.Links.Janitor]
    else
      []
    end
  end

  defp mass_reindexer_children do
    if Application.get_env(:liminal, :start_mass_reindexer, true) do
      [Liminal.Links.MassReindexer]
    else
      []
    end
  end

  defp maybe_create_db do
    if auto_migrate?() do
      Liminal.Repo.__adapter__().storage_up(Liminal.Repo.config())
    end
  end

  defp auto_migrate? do
    Application.get_env(:liminal, :auto_migrate, true)
  end
end
