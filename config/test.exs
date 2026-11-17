import Config

# Configure your database.
#
# Tests use a separate database on the same PostgreSQL server as development.
# The local overlay creates `turbo_falcon_test` as a CNPG Database owned by the
# `turbo_falcon` role, so provision the local overlay once before running tests
# (`./deployment/deploy_local.sh`).
#
# Set TEST_DATABASE_URL to override the derived URL. Tests use the Ecto SQL
# sandbox, so each test rolls back and the schema is reused between runs.
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
test_database_url =
  System.get_env("TEST_DATABASE_URL") ||
    case System.get_env("DATABASE_URL") do
      nil ->
        "postgresql://localhost/turbo_falcon_test"

      url ->
        url
        |> URI.parse()
        |> Map.put(:path, "/turbo_falcon_test")
        |> URI.to_string()
    end

config :turbo_falcon, TurboFalcon.Repo,
  url: test_database_url,
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :turbo_falcon, TurboFalconWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "U/xhqTm4Qpjfsu7j31lzQOrvpDx0g2PNmDiYLCWOSNH3voyxtNLbwggibngIjjZf",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning
# Do not start the scheduler or the summarization pipeline in tests; they would
# poll the sandboxed database from unowned processes and could hit the LLM API.
config :turbo_falcon, start_pipeline: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
