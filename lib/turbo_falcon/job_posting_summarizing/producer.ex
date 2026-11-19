defmodule TurboFalcon.JobPostingSummarizing.Producer do
  use GenStage
  alias TurboFalcon.HackerNews.JobPosting
  alias TurboFalcon.Observability.ErrorReporter
  require Logger
  import Ecto.Query

  def start_link(_) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    {:producer, %{}, dispatcher: GenStage.DemandDispatcher}
  end

  @impl true
  def handle_demand(demand, state) do
    job_postings = fetch_job_postings(demand)

    if job_postings |> length() < demand do
      Process.send_after(self(), :check, 10_000)
    end

    Logger.info("Producing #{length(job_postings)} job postings for summarization")
    {:noreply, job_postings, state}
  end

  @impl true
  def handle_info(:check, state) do
    postings = fetch_job_postings(1)

    case postings do
      [] ->
        Process.send_after(self(), :check, 10_000)
        {:noreply, [], state}

      postings when is_list(postings) ->
        count = length(postings)
        Logger.info("Fetched #{count} job postings to summarize")
        {:noreply, postings, state}

      {:error, reason} ->
        ErrorReporter.report_message(
          "database_error",
          "Failed to fetch job postings: #{reason}",
          operation: "summarize_job_posting"
        )

        Process.send_after(self(), :check, 10_000)
        {:noreply, [], state}
    end
  end

  defp fetch_job_postings(demand) do
    cutoff = TurboFalcon.JobPostingWindow.cutoff()

    JobPosting
    |> where([jp], not jp.summarized and not jp.deleted)
    |> where([jp], jp.timestamp >= ^cutoff)
    |> order_by([jp], desc: jp.timestamp)
    |> limit(^demand)
    |> TurboFalcon.Repo.all()
  end
end
