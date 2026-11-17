defmodule TurboFalcon.HackerNews.Scheduler do
  use Quantum, otp_app: :turbo_falcon

  alias TurboFalcon.HackerNews.{JobPosting, JobThread, WebApiClient}
  alias TurboFalcon.HtmlSanitizer
  alias TurboFalcon.Repo

  require Logger

  @look_back_threads 30
  @thread_fetch_concurrency 10
  @thread_timeout 120_000
  @placeholder_texts ["[dead]", "[flagged]"]

  def run(client_module \\ WebApiClient) do
    client = client_module.new()

    case client_module.get_who_is_hiring_user(client) do
      {:ok, %{body: %{"submitted" => submitted}}} when is_list(submitted) ->
        submitted
        |> Enum.take(@look_back_threads)
        |> fetch_threads(client_module, client)
        |> Enum.filter(&who_is_hiring_thread?/1)
        |> Enum.map(&process_job_thread(&1, client_module, client))
        |> Enum.reject(&is_nil/1)
        |> await_tasks()

      {:ok, %{status: status}} ->
        Logger.error("Unexpected whoishiring response status: #{status}")

      {:error, reason} ->
        Logger.error("Failed to fetch whoishiring submissions: #{inspect(reason)}")
    end

    :ok
  end

  defp fetch_threads(ids, client_module, client) do
    ids
    |> Task.async_stream(&get_thread_data(client_module, client, &1),
      max_concurrency: @thread_fetch_concurrency,
      timeout: @thread_timeout,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, body}} ->
        [body]

      {:ok, {:error, reason}} ->
        Logger.error("Failed to fetch thread: #{inspect(reason)}")
        []

      {:exit, reason} ->
        Logger.error("Thread fetch exited: #{inspect(reason)}")
        []
    end)
  end

  defp get_thread_data(client_module, client, id) do
    case client_module.get_item_by_id(client, id) do
      {:ok, %{body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp who_is_hiring_thread?(item_body) do
    case Map.get(item_body, "title") do
      title when is_binary(title) -> String.starts_with?(title, "Ask HN: Who is hiring?")
      _ -> false
    end
  end

  defp process_job_thread(item_body, client_module, client) do
    item_id = Map.get(item_body, "id")
    has_changed? = upsert_job_thread(item_body)
    created_at = Map.get(item_body, "time", 0)
    current_time = DateTime.utc_now() |> DateTime.to_unix()
    is_recent = current_time - created_at < TurboFalcon.JobPostingWindow.seconds()

    if has_changed? or is_recent do
      Logger.info("Processing story for job thread (#{item_id}): #{Map.get(item_body, "title")}")

      Task.async(fn ->
        process_thread(item_id, Map.get(item_body, "kids", []), client_module, client)
      end)
    else
      Logger.info("Skipping story for job thread (#{item_id}): #{Map.get(item_body, "title")}")

      nil
    end
  end

  defp process_thread(item_id, kids, client_module, client) do
    process_postings(kids, client_module, client)
  rescue
    exception ->
      Logger.error("Failed to process thread #{item_id}: #{Exception.message(exception)}")
  catch
    kind, reason ->
      Logger.error("Failed to process thread #{item_id}: #{inspect({kind, reason})}")
  end

  defp upsert_job_thread(item_body) do
    item_id = Map.get(item_body, "id")
    current_postings = Map.get(item_body, "descendants", 0)

    case Repo.get_by(JobThread, item_id: item_id) do
      %JobThread{} = job_thread ->
        if job_thread.postings != current_postings do
          Logger.info("Updating job thread (#{item_id}): #{Map.get(item_body, "title")}")

          job_thread
          |> JobThread.changeset(%{postings: current_postings})
          |> Repo.update()
          |> write_succeeded?("update job thread #{item_id}")
        else
          false
        end

      nil ->
        Logger.info("Inserting new job thread (#{item_id}): #{Map.get(item_body, "title")}")

        %JobThread{}
        |> JobThread.changeset(%{
          item_id: item_id,
          title: Map.get(item_body, "title"),
          created: Map.get(item_body, "time"),
          postings: current_postings
        })
        |> Repo.insert()
        |> write_succeeded?("insert job thread #{item_id}")
    end
  end

  defp process_postings(kids, client_module, client) do
    Enum.each(kids, fn item_id ->
      case client_module.get_item_by_id(client, item_id) do
        {:ok, %{body: body}} when is_map(body) ->
          process_posting(body, item_id)

        {:ok, %{status: status}} ->
          Logger.error("Unexpected status fetching item #{item_id}: #{status}")

        {:error, reason} ->
          Logger.error("Failed to fetch item #{item_id}: #{inspect(reason)}")
      end
    end)
  end

  defp process_posting(body, item_id) do
    current_posting = Repo.get_by(JobPosting, item_id: item_id)
    text = sanitize_text(body)

    cond do
      deleted?(body) ->
        maybe_mark_post_deleted(current_posting, item_id)

      text == "" ->
        Logger.debug("Job post #{item_id} has no text, skipping")

      is_nil(current_posting) ->
        insert_new_job_post(body, item_id, text)

      true ->
        update_job_post_text(current_posting, text, item_id)
    end
  end

  # HN keeps `by` on dead and flagged comments and replaces their text with a
  # placeholder, so the author field alone is not enough. The flags are the
  # source of truth; the placeholders are only a fallback for payloads that
  # predate them.
  defp deleted?(body) do
    body["deleted"] == true or
      body["dead"] == true or
      is_nil(body["by"]) or
      body["text"] in @placeholder_texts
  end

  defp sanitize_text(body) do
    HtmlSanitizer.sanitize(Map.get(body, "text") || "")
  end

  defp maybe_mark_post_deleted(nil, _item_id), do: :ok
  defp maybe_mark_post_deleted(%JobPosting{deleted: true}, _item_id), do: :ok

  defp maybe_mark_post_deleted(current_posting, item_id) do
    Logger.debug("Job post #{item_id} deleted")

    current_posting
    |> JobPosting.changeset(%{deleted: true})
    |> Repo.update()
    |> handle_write("mark job post #{item_id} deleted")
  end

  defp insert_new_job_post(body, item_id, text) do
    Logger.debug("Inserting new job post: #{item_id}")

    %JobPosting{}
    |> JobPosting.changeset(%{
      item_id: item_id,
      thread_id: Map.get(body, "parent"),
      user: Map.get(body, "by"),
      text: text,
      timestamp: Map.get(body, "time")
    })
    |> Repo.insert()
    |> handle_write("insert job post #{item_id}")
    |> case do
      {:ok, posting} ->
        broadcast(posting)
        posting

      {:error, _changeset} ->
        nil
    end
  end

  defp update_job_post_text(%JobPosting{text: text}, text, item_id) do
    Logger.debug("Job post #{item_id} unchanged")
  end

  defp update_job_post_text(current_posting, text, item_id) do
    Logger.debug("Updating job post: #{item_id}")

    current_posting
    |> JobPosting.changeset(%{text: text})
    |> Repo.update()
    |> handle_write("update job post #{item_id}")
    |> case do
      {:ok, posting} ->
        broadcast(posting)
        posting

      {:error, _changeset} ->
        nil
    end
  end

  defp handle_write({:ok, _record} = result, _context), do: result

  defp handle_write({:error, changeset}, context) do
    Logger.error("Failed to #{context}: #{inspect(changeset.errors)}")
    {:error, changeset}
  end

  defp write_succeeded?(result, context) do
    case handle_write(result, context) do
      {:ok, _record} -> true
      {:error, _changeset} -> false
    end
  end

  defp broadcast(posting) do
    Phoenix.PubSub.broadcast(
      TurboFalcon.PubSub,
      "job_postings:#{posting.thread_id}",
      {:job_posting_updated, posting}
    )
  end

  defp await_tasks(tasks) do
    tasks
    |> Task.yield_many(@thread_timeout)
    |> Enum.each(fn
      {_task, {:ok, _result}} ->
        :ok

      {_task, {:exit, reason}} ->
        Logger.error("Thread task exited: #{inspect(reason)}")

      {task, nil} ->
        Logger.error("Thread task timed out after #{@thread_timeout}ms")
        Task.shutdown(task, :brutal_kill)
    end)
  end
end
