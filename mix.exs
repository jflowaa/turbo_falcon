defmodule TurboFalcon.MixProject do
  use Mix.Project

  def project do
    [
      app: :turbo_falcon,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {TurboFalcon.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:finch, "~> 0.24"},
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:html_sanitize_ex, "~> 1.5"},
      {:bandit, "~> 1.14"},
      {:req, "~> 0.7"},
      {:gen_stage, "~> 1.3"},
      {:quantum, "~> 3.5"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_exporter, "~> 1.11"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_bandit, "~> 0.3"},
      {:opentelemetry_ecto, "~> 1.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "db.migrate", "assets.setup", "assets.build"],
      "db.migrate": [&db_migrate/1],
      test: ["db.migrate", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind turbo_falcon", "esbuild turbo_falcon"],
      "assets.deploy": [
        "tailwind turbo_falcon --minify",
        "esbuild turbo_falcon --minify",
        "phx.digest"
      ]
    ]
  end

  defp db_migrate(_args) do
    run_dbmate(["--migration-lock", "migrate"])
  end

  defp run_dbmate(args) do
    Mix.Task.run("app.config")

    url =
      :turbo_falcon
      |> Application.fetch_env!(TurboFalcon.Repo)
      |> Keyword.fetch!(:url)

    case System.cmd("dbmate", args,
           env: [{"DATABASE_URL", url}],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        IO.write(output)
        :ok

      {output, code} ->
        Mix.raise("dbmate #{Enum.join(args, " ")} failed with exit code #{code}:\n#{output}")
    end
  end
end
