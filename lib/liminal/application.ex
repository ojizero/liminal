defmodule Liminal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_create_db()

    children =
      [
        LiminalWeb.Telemetry,
        Liminal.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:liminal, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:liminal, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Liminal.PubSub},
        {Task.Supervisor, name: Liminal.Links.IndexerTaskSupervisor},
        # Start to serve requests, typically the last entry
        LiminalWeb.Endpoint
      ] ++ janitor_children()

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

  defp maybe_create_db do
    unless skip_migrations?() do
      Liminal.Repo.__adapter__().storage_up(Liminal.Repo.config())
    end
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
