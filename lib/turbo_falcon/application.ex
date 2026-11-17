defmodule TurboFalcon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        TurboFalconWeb.Telemetry,
        TurboFalcon.Repo,
        {Phoenix.PubSub, name: TurboFalcon.PubSub},
        # HTTP pools for the outbound API clients. They are supervised so that
        # a crash in whichever process happened to call `new/0` first cannot
        # take the pool down, and so there is no start-up race between callers.
        {Finch, name: TurboFalcon.HackerNews.Finch, pools: %{default: [size: 100]}},
        {Finch, name: TurboFalcon.Groq.Finch, pools: %{default: [size: 10]}},
        {Finch, name: TurboFalcon.Gemini.Finch, pools: %{default: [size: 10]}}
      ] ++ pipeline_children() ++ [TurboFalconWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TurboFalcon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp pipeline_children do
    if Application.get_env(:turbo_falcon, :start_pipeline, true) do
      [
        TurboFalcon.HackerNews.Scheduler,
        TurboFalcon.JobPostingSummarizing.Producer,
        {TurboFalcon.JobPostingSummarizing.Consumer,
         [id: :consumer_1, client_module: job_posting_summary_client()]}
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TurboFalconWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp job_posting_summary_client do
    Application.fetch_env!(:turbo_falcon, :job_posting_summary_client)
  end
end
