import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/turbo_falcon start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :turbo_falcon, TurboFalconWeb.Endpoint, server: true
end

# ## Observability
#
# Logs are JSON on stdout and are tailed by the platform collector. Traces go
# over OTLP/gRPC to the shared collector on the platform `observability`
# network. Both the local and production deployments use MIX_ENV=prod, so the
# environment label is chosen explicitly rather than from MIX_ENV alone.
deploy_environment =
  System.get_env("DEPLOY_ENV") ||
    if config_env() == :prod do
      if String.ends_with?(System.get_env("PHX_HOST", ""), ".localhost"),
        do: "local",
        else: "production"
    else
      Atom.to_string(config_env())
    end

app_version =
  case Application.spec(:turbo_falcon, :vsn) do
    nil -> "unknown"
    vsn -> List.to_string(vsn)
  end

deployed_version =
  case System.get_env("IMAGE_TAG") do
    value when value in [nil, ""] -> app_version
    value -> value
  end

config :turbo_falcon, :observability,
  service: "turbo_falcon",
  environment: deploy_environment,
  version: deployed_version

otel_enabled =
  case System.get_env("OTEL_ENABLED") do
    nil -> config_env() == :prod
    value -> value not in ["false", "0", "no"]
  end

config :opentelemetry,
  log_level: :warning,
  resource: [
    service: %{
      name: "turbo_falcon",
      version: deployed_version
    },
    "deployment.environment": deploy_environment
  ],
  traces_exporter: if(otel_enabled, do: {:opentelemetry_exporter, %{}}, else: :none),
  # The platform collector has no metrics pipeline; traces and logs only.
  metrics_exporter: :none

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgresql://turbo_falcon:PASSWORD@postgres-rw.webapps:5432/turbo_falcon
      """

  config :turbo_falcon, TurboFalcon.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      For example: turbo-falcon.jack-develops.com
      """

  port = String.to_integer(System.get_env("PORT") || "4002")

  config :turbo_falcon, TurboFalconWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :turbo_falcon, TurboFalconWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :turbo_falcon, TurboFalconWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
