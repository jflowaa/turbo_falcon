# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :turbo_falcon,
  ecto_repos: [TurboFalcon.Repo],
  generators: [timestamp_type: :utc_datetime],
  product_name: "Hacker News Job Board",
  job_posting_summary_client: TurboFalcon.Groq.WebApiClient

# Configures the endpoint
config :turbo_falcon, TurboFalconWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TurboFalconWeb.ErrorHTML, json: TurboFalconWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TurboFalcon.PubSub,
  live_view: [signing_salt: "pl8yz5gi"]

config :turbo_falcon, TurboFalcon.HackerNews.Scheduler,
  overlap: false,
  timezone: :utc,
  jobs: [
    {"*/30 * * * *", {TurboFalcon.HackerNews.Scheduler, :run, []}}
  ]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :turbo_falcon, TurboFalcon.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  turbo_falcon: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  turbo_falcon: [
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
if config_env() in [:dev, :test] do
  import_config ".env.exs"
end

import_config "#{config_env()}.exs"
