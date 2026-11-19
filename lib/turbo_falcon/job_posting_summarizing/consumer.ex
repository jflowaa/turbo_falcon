defmodule TurboFalcon.JobPostingSummarizing.Consumer do
  use GenStage
  alias TurboFalcon.HackerNews.JobPosting
  alias TurboFalcon.HtmlSanitizer
  alias TurboFalcon.Observability.ErrorReporter
  require Logger

  # How many postings to pull from the producer at a time. They are summarized
  # sequentially, so this only saves GenStage round trips.
  @batch_size 5
  @rate_limit_pause 60_000

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    client_module = Keyword.fetch!(opts, :client_module)

    {:consumer,
     %{
       api_client_module: client_module,
       api_client: client_module.new(),
       paused: false,
       subscription: nil
     }, subscribe_to: [TurboFalcon.JobPostingSummarizing.Producer]}
  end

  @impl true
  def handle_subscribe(:producer, _opts, from, state) do
    GenStage.ask(from, @batch_size)
    {:manual, %{state | subscription: from}}
  end

  @impl true
  def handle_events(job_postings, _from, %{paused: true} = state) do
    Logger.info(
      "Paused; dropping #{length(job_postings)} postings (they stay unsummarized in the DB)"
    )

    {:noreply, [], state}
  end

  @impl true
  def handle_events(job_postings, _from, state) do
    Logger.info("Processing #{length(job_postings)} job postings for summarization...")

    result =
      Enum.reduce_while(job_postings, :ok, fn job_posting, _acc ->
        case summarize_job_posting(state.api_client_module, state.api_client, job_posting) do
          :ok -> {:cont, :ok}
          :rate_limited -> {:halt, :rate_limited}
        end
      end)

    # On a rate limit the pause message is already queued and the resume handler
    # asks again. Otherwise keep the pipe full.
    if result == :ok and job_postings != [] and state.subscription do
      GenStage.ask(state.subscription, @batch_size)
    end

    {:noreply, [], state}
  end

  defp summarize_job_posting(client_module, client, job_posting) do
    case client_module.get_summary_of_job_posting(client, job_posting.text) do
      {:ok, response} when response.status == 200 ->
        case get_summary_from_response(response) do
          {:ok, summary} ->
            Logger.info("Summarized job posting #{job_posting.item_id}")
            update_job_posting(job_posting, summary)

          {:error, reason} ->
            ErrorReporter.report_message(
              "llm_response_error",
              "Failed to summarize job posting #{job_posting.item_id}: #{inspect(reason)}",
              operation: "summarize_job_posting"
            )
        end

        :ok

      {:ok, response} when response.status == 429 ->
        Logger.warning(
          "Rate limited (429) on job posting #{job_posting.item_id}, pausing for #{@rate_limit_pause}ms"
        )

        send(self(), :pause_for_rate_limit)
        :rate_limited

      {:ok, response} ->
        ErrorReporter.report_message(
          "upstream_status",
          "Failed to summarize job posting #{job_posting.item_id}: unexpected status #{response.status}",
          operation: "summarize_job_posting",
          status: response.status
        )

        :ok

      {:error, reason} ->
        ErrorReporter.report_message(
          "upstream_error",
          "Failed to summarize job posting #{job_posting.item_id}: #{inspect(reason)}",
          operation: "summarize_job_posting"
        )

        :ok
    end
  end

  @impl true
  def handle_info(:pause_for_rate_limit, state) do
    Process.send_after(self(), :resume_after_pause, @rate_limit_pause)
    {:noreply, [], %{state | paused: true}}
  end

  @impl true
  def handle_info(:resume_after_pause, state) do
    Logger.info("Resuming consumer after rate limit pause")
    if state.subscription, do: GenStage.ask(state.subscription, @batch_size)
    {:noreply, [], %{state | paused: false}}
  end

  defp update_job_posting(job_posting, summary) do
    changeset =
      JobPosting.changeset(job_posting, %{
        summarized: true,
        summarized_text: sanitize_summary(summary),
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
        ErrorReporter.report_message(
          "database_error",
          "Failed to update job posting #{job_posting.item_id}: #{inspect(changeset.errors)}",
          operation: "summarize_job_posting"
        )
    end
  end

  defp get_summary_from_response(%{body: body}) when is_map(body) do
    cond do
      Map.has_key?(body, "candidates") -> gemini_summary(body)
      Map.has_key?(body, "choices") -> openai_summary(body)
      true -> {:error, :unexpected_format}
    end
  end

  defp get_summary_from_response(_response), do: {:error, :unexpected_format}

  defp gemini_summary(body) do
    body
    |> Map.get("candidates", [])
    |> List.first(%{})
    |> Map.get("content", %{})
    |> Map.get("parts", [])
    |> List.first(%{})
    |> Map.get("text")
    |> normalize_summary()
  end

  defp openai_summary(body) do
    body
    |> Map.get("choices", [])
    |> List.first(%{})
    |> Map.get("message", %{})
    |> Map.get("content")
    |> normalize_summary()
  end

  # A missing or empty completion must not be stored as `summarized: true` with
  # no text: the producer filters on `not summarized`, so the posting would
  # never be retried and the card would render blank.
  defp normalize_summary(nil), do: {:error, :unexpected_format}

  defp normalize_summary(text) when is_binary(text) do
    case clean_markdown_code_block(text) do
      "" -> {:error, :empty_response}
      cleaned -> {:ok, cleaned}
    end
  end

  defp normalize_summary(_other), do: {:error, :unexpected_format}

  @code_fence_start ~r/\A```[a-zA-Z0-9_+-]*\s*/
  @code_fence_end ~r/\s*```\z/

  defp clean_markdown_code_block(text) do
    text
    |> String.trim()
    |> String.replace(@code_fence_start, "")
    |> String.replace(@code_fence_end, "")
    |> String.trim()
  end

  defp sanitize_summary(summary) when is_binary(summary), do: HtmlSanitizer.sanitize(summary)
end
