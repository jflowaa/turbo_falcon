defmodule TurboFalcon.HackerNews.Scheduler do
  use Quantum, otp_app: :turbo_falcon
  alias TurboFalcon.HackerNews.WebApiClient, as: HackerNewsApiClient
  require Logger

  @look_back_threads 30
  @days_old_threshold_in_seconds 20 * 24 * 60 * 60

  def run() do
    client = HackerNewsApiClient.new()
    {:ok, response} = HackerNewsApiClient.get_who_is_hiring_user(client)

    response
    |> Map.get(:body)
    |> Map.get("submitted")
    |> Enum.take(@look_back_threads)
    |> Enum.map(&get_thread_data(client, &1))
    |> Enum.filter(&who_is_hiring_thread?/1)
    |> Enum.map(&process_job_thread/1)
    |> Enum.filter(& &1)
    |> Enum.each(&Task.await(&1, :infinity))

    :ok
  end

  defp get_thread_data(client, id) do
    {:ok, item_response} = HackerNewsApiClient.get_item_by_id(client, id)
    Map.get(item_response, :body)
  end

  defp who_is_hiring_thread?(item_body) do
    String.starts_with?(Map.get(item_body, "title", ""), "Ask HN: Who is hiring?")
  end

  defp process_job_thread(item_body) do
    has_changed? = upsert_job_thread(item_body)
    created_at = Map.get(item_body, "time", 0)
    current_time = DateTime.utc_now() |> DateTime.to_unix()
    is_recent = current_time - created_at < @days_old_threshold_in_seconds

    if has_changed? or is_recent do
      Logger.info(
        "Processing story for job thread (#{Map.get(item_body, "id")}): #{Map.get(item_body, "title")}"
      )

      Task.async(fn ->
        process_postings(Map.get(item_body, "kids", []))
      end)
    else
      Logger.info(
        "Skipping story for job thread (#{Map.get(item_body, "id")}): #{Map.get(item_body, "title")}"
      )

      nil
    end
  end

  defp upsert_job_thread(item_body) do
    item_id = Map.get(item_body, "id")
    current_postings = Map.get(item_body, "descendants", 0)

    case TurboFalcon.Repo.get_by(TurboFalcon.HackerNews.JobThread, item_id: item_id) do
      %TurboFalcon.HackerNews.JobThread{} = job_thread ->
        if job_thread.postings != current_postings do
          Logger.info("Updating job thread (#{item_id}): #{Map.get(item_body, "title")}")

          job_thread
          |> TurboFalcon.HackerNews.JobThread.changeset(%{postings: current_postings})
          |> TurboFalcon.Repo.update!()

          true
        else
          false
        end

      nil ->
        Logger.info("Inserting new job thread (#{item_id}): #{Map.get(item_body, "title")}")

        %TurboFalcon.HackerNews.JobThread{}
        |> TurboFalcon.HackerNews.JobThread.changeset(%{
          item_id: item_id,
          title: Map.get(item_body, "title"),
          created: Map.get(item_body, "time"),
          postings: current_postings
        })
        |> TurboFalcon.Repo.insert!()

        true
    end
  end

  defp process_postings(kids) do
    client = HackerNewsApiClient.new()

    Enum.each(kids, fn item_id ->
      {:ok, response} = HackerNewsApiClient.get_item_by_id(client, item_id)
      body = response.body

      current_posting =
        TurboFalcon.Repo.get_by(TurboFalcon.HackerNews.JobPosting, item_id: item_id)

      cond do
        is_nil(Map.get(body, "by")) ->
          maybe_mark_post_deleted(current_posting, item_id)

        is_nil(current_posting) ->
          insert_new_job_post(body, item_id)

        current_posting.text != Map.get(body, "text", "") ->
          update_job_post_text(current_posting, body, item_id)

        true ->
          Logger.debug("Job post #{item_id} unchanged")
      end
    end)
  end

  defp maybe_mark_post_deleted(nil, _item_id), do: :ok

  defp maybe_mark_post_deleted(current_posting, item_id) do
    Logger.debug("Job post #{item_id} deleted")

    current_posting
    |> TurboFalcon.HackerNews.JobPosting.changeset(%{deleted: true})
    |> TurboFalcon.Repo.update!()
  end

  defp insert_new_job_post(body, item_id) do
    Logger.debug("Inserting new job post: #{item_id}")

    posting =
      %TurboFalcon.HackerNews.JobPosting{}
      |> TurboFalcon.HackerNews.JobPosting.changeset(%{
        item_id: item_id,
        thread_id: Map.get(body, "parent"),
        user: Map.get(body, "by"),
        text: Map.get(body, "text", ""),
        timestamp: Map.get(body, "time"),
        deleted: Map.get(body, "deleted", false)
      })
      |> TurboFalcon.Repo.insert!()

    Phoenix.PubSub.broadcast(
      TurboFalcon.PubSub,
      "job_postings:#{posting.thread_id}",
      {:job_posting_updated, posting}
    )

    posting
  end

  defp update_job_post_text(current_posting, body, item_id) do
    Logger.debug("Updating job post: #{item_id}")

    posting =
      current_posting
      |> TurboFalcon.HackerNews.JobPosting.changeset(%{text: Map.get(body, "text", "")})
      |> TurboFalcon.Repo.update!()

    Phoenix.PubSub.broadcast(
      TurboFalcon.PubSub,
      "job_postings:#{posting.thread_id}",
      {:job_posting_updated, posting}
    )

    posting
  end
end
