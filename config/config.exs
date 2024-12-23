# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :connections_multiplayer,
  ecto_repos: [ConnectionsMultiplayer.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :connections_multiplayer, ConnectionsMultiplayerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: ConnectionsMultiplayerWeb.ErrorHTML,
      json: ConnectionsMultiplayerWeb.ErrorJSON
    ],
    layout: false
  ],
  pubsub_server: ConnectionsMultiplayer.PubSub,
  live_view: [signing_salt: "8xCSdA1e"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  connections_multiplayer: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --external:/images/avatars/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  connections_multiplayer: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
