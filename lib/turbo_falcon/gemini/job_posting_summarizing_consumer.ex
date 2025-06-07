defmodule TurboFalcon.Gemini.JobPostingSummarizingConsumer do
  use GenStage
  alias TurboFalcon.HackerNews.JobPosting
  alias TurboFalcon.Gemini.WebApiClient
  require Logger

  def start_link(_) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    {:consumer, %{gemini_client: WebApiClient.new(), paused: false, subscription: nil},
     subscribe_to: [TurboFalcon.Gemini.JobPostingSummarizingProducer]}
  end

  @impl true
  def handle_subscribe(:producer, _opts, from, state) do
    GenStage.ask(from, 1)
    {:manual, %{state | subscription: from}}
  end

  @impl true
  def handle_events(job_postings, _from, %{paused: true} = state) do
    Logger.info(
      "Processing paused will NOT process #{length(job_postings)} job postings for summarization..."
    )

    {:noreply, [], state}
  end

  @impl true
  def handle_events(job_postings, _from, state) do
    Logger.info("Processing #{length(job_postings)} job postings for summarization...")

    Enum.each(job_postings, fn job_posting ->
      summarize_job_posting(state.gemini_client, job_posting)
    end)

    if state.subscription, do: GenStage.ask(state.subscription, 1)
    {:noreply, [], state}
  end

  defp summarize_job_posting(client, job_posting) do
    case WebApiClient.get_summary_of_job_posting(client, job_posting.text) do
      {:ok, response} when response.status == 200 ->
        Logger.info("Summarized job posting #{job_posting.item_id}")
        update_job_posting(job_posting, get_summary_from_response(response))

      {:ok, response} when response.status == 429 ->
        Logger.warning(
          "Rate limited (429) on job posting #{job_posting.item_id}, pausing for 60s"
        )

        send(self(), :pause_for_rate_limit)

      {:ok, response} ->
        reason = "Unexpected response status: #{response.status}"
        Logger.error("Failed to summarize job posting #{job_posting.item_id}: #{reason}")

      {:error, reason} ->
        Logger.error("Failed to summarize job posting #{job_posting.item_id}: #{reason}")
    end
  end

  @impl true
  def handle_info(:pause_for_rate_limit, state) do
    Process.send_after(self(), :resume_after_pause, 60_000)
    {:noreply, [], %{state | paused: true}}
  end

  @impl true
  def handle_info(:resume_after_pause, state) do
    Logger.info("Resuming consumer after rate limit pause")
    if state.subscription, do: GenStage.ask(state.subscription, 1)
    {:noreply, [], %{state | paused: false}}
  end

  defp update_job_posting(job_posting, summary) do
    changeset =
      JobPosting.changeset(job_posting, %{
        summarized: true,
        summarized_text: summary,
        summarized_at: DateTime.utc_now()
      })

    case TurboFalcon.Repo.update(changeset) do
      {:ok, updated_job_posting} ->
        Phoenix.PubSub.broadcast(
          TurboFalcon.PubSub,
          "job_postings:#{updated_job_posting.thread_id}",
          {:job_posting_updated, updated_job_posting}
        )

        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to update job posting #{job_posting.item_id}: #{inspect(changeset.errors)}"
        )
    end
  end

  defp get_summary_from_response(response) do
    response.body
    |> Map.get("candidates", [])
    |> List.first(%{})
    |> Map.get("content", %{})
    |> Map.get("parts", [])
    |> List.first(%{})
    |> Map.get("text", "")
    |> clean_markdown_code_block()
  end

  defp clean_markdown_code_block(text) when is_binary(text) do
    text
    |> String.trim_leading("```html")
    |> String.trim_trailing("```")
    |> String.trim()
  end

  defp clean_markdown_code_block(_), do: nil
end
