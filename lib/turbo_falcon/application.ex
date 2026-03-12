defmodule TurboFalcon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TurboFalconWeb.Telemetry,
      TurboFalcon.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:turbo_falcon, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:turbo_falcon, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TurboFalcon.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: TurboFalcon.Finch},
      # Start a worker by calling: TurboFalcon.Worker.start_link(arg)
      # {TurboFalcon.Worker, arg},
      TurboFalcon.HackerNews.Scheduler,
      TurboFalcon.HackerNews.JobServer,
      TurboFalcon.JobPostingSummarizing.Producer,
      {TurboFalcon.JobPostingSummarizing.Consumer,
       [id: :consumer_1, client_module: job_posting_summary_client()]},
      # Start to serve requests, typically the last entry
      TurboFalconWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TurboFalcon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TurboFalconWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") != nil
  end

  defp job_posting_summary_client do
    Application.fetch_env!(:turbo_falcon, :job_posting_summary_client)
  end
end
