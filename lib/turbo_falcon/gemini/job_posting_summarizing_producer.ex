defmodule TurboFalcon.Gemini.JobPostingSummarizingProducer do
  use GenStage
  alias TurboFalcon.HackerNews.JobPosting
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
        Logger.error("Failed to fetch job postings: #{reason}")
        Process.send_after(self(), :check, 10_000)
        {:noreply, [], state}
    end
  end

  defp fetch_job_postings(demand) do
    thirty_days_ago =
      DateTime.utc_now()
      |> DateTime.add(-30 * 24 * 60 * 60, :second)

    JobPosting
    |> where([jp], not jp.summarized and not jp.deleted)
    |> where([jp], jp.timestamp >= ^thirty_days_ago)
    |> order_by([jp], desc: jp.timestamp)
    |> limit(^demand)
    |> TurboFalcon.Repo.all()
  end
end
