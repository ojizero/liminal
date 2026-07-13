# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :liminal, :scopes,
  user: [
    default: true,
    module: Liminal.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Liminal.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :liminal,
  ecto_repos: [Liminal.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :liminal, Liminal.Retry,
  max_attempts: 10,
  base_delay_seconds: 300,
  max_delay_seconds: 86_400

config :liminal, Liminal.Links.Reindex,
  batch_size: 3,
  interval_ms: 2_000

config :liminal, Liminal.Repo,
  migration_primary_key: [name: :id, type: :binary_id, null: false],
  migration_foreign_key: [type: :binary_id]

# Configure the endpoint
config :liminal, LiminalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LiminalWeb.ErrorHTML, json: LiminalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Liminal.PubSub,
  live_view: [signing_salt: "yjqKCHEh"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.28.1",
  liminal: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.2",
  liminal: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
