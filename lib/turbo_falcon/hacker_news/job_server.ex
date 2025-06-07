defmodule TurboFalcon.HackerNews.JobServer do
  use GenServer, restart: :transient
  require Logger
  import Ecto.Query

  # Client API
  def get_latest_job_thread do
    GenServer.call(__MODULE__, :get_latest_job_thread)
  end

  def get_job_threads do
    GenServer.call(__MODULE__, :get_job_threads)
  end

  def get_job_postings(job_thread_id) do
    GenServer.call(__MODULE__, {:get_job_postings, job_thread_id})
  end

  def get_job_postings(job_thread_id, filters, is_exclusive \\ false) do
    GenServer.call(__MODULE__, {:get_job_postings, job_thread_id, filters, is_exclusive})
  end

  def clear_all_summaries do
    GenServer.call(__MODULE__, :clear_all_summaries)
  end

  def clear_summary(job_posting_id) do
    GenServer.call(__MODULE__, {:clear_summary, job_posting_id})
  end

  def get_job_posting(id) do
    GenServer.call(__MODULE__, {:get_job_posting, id})
  end

  def mark_dead_as_deleted do
    GenServer.call(__MODULE__, :mark_dead_as_deleted)
  end

  # Server API
  def start_link(opts) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, _}} ->
        :ignore
    end
  end

  def init(_) do
    {:ok, %{}}
  end

  def handle_call(:get_latest_job_thread, _from, state) do
    job_thread =
      TurboFalcon.HackerNews.JobThread
      |> order_by([jt], desc: jt.item_id)
      |> limit(1)
      |> TurboFalcon.Repo.one()

    cond do
      is_nil(job_thread) ->
        {:reply, {:error, "No job threads found"}, state}

      true ->
        {:reply, {:ok, job_thread}, state}
    end
  end

  def handle_call(:get_job_threads, _from, state) do
    job_threads =
      TurboFalcon.HackerNews.JobThread
      |> order_by([jt], desc: jt.item_id)
      |> TurboFalcon.Repo.all()

    cond do
      is_nil(job_threads) ->
        {:reply, {:error, "No job threads found"}, state}

      true ->
        {:reply, {:ok, job_threads}, state}
    end
  end

  def handle_call({:get_job_postings, job_thread_id}, _from, state) do
    job_postings =
      TurboFalcon.HackerNews.JobPosting
      |> where([jp], jp.thread_id == ^job_thread_id)
      |> order_by([jp], desc: jp.timestamp)
      |> TurboFalcon.Repo.all()

    cond do
      is_nil(job_postings) ->
        {:reply, {:error, "No job postings found for thread #{job_thread_id}"}, state}

      true ->
        {:reply, {:ok, job_postings}, state}
    end
  end

  def handle_call({:get_job_postings, job_thread_id, filters, is_exclusive}, _from, state) do
    base_query =
      from jp in TurboFalcon.HackerNews.JobPosting,
        where: jp.thread_id == ^job_thread_id

    dynamic_filter =
      Enum.reduce(filters, nil, fn filter, dynamic_acc ->
        expr =
          dynamic(
            [
              jp
            ],
            like(fragment("LOWER(?)", jp.text), ^("%" <> String.downcase(filter) <> "%"))
          )

        cond do
          dynamic_acc == nil -> expr
          is_exclusive -> dynamic([jp], ^dynamic_acc and ^expr)
          true -> dynamic([jp], ^dynamic_acc or ^expr)
        end
      end)

    query =
      if filters == [] do
        base_query
      else
        from jp in base_query, where: ^dynamic_filter
      end

    job_postings =
      query
      |> order_by([jp], desc: jp.timestamp)
      |> TurboFalcon.Repo.all()

    cond do
      job_postings == [] ->
        {:reply, {:error, "No job postings found for thread #{job_thread_id}"}, state}

      true ->
        {:reply, {:ok, job_postings}, state}
    end
  end

  def handle_call(:clear_all_summaries, _from, state) do
    {count, _} =
      TurboFalcon.HackerNews.JobPosting
      |> TurboFalcon.Repo.update_all(
        set: [
          summarized: false,
          summarized_text: nil,
          summarized_at: nil
        ]
      )

    {:reply, {:ok, count}, state}
  end

  def handle_call({:clear_summary, job_posting_id}, _from, state) do
    import Ecto.Query

    {count, _} =
      TurboFalcon.HackerNews.JobPosting
      |> where([jp], jp.id == ^job_posting_id)
      |> TurboFalcon.Repo.update_all(
        set: [
          summarized: false,
          summarized_text: nil,
          summarized_at: nil
        ]
      )

    {:reply, {:ok, count}, state}
  end

  def handle_call({:get_job_posting, id}, _from, state) do
    result =
      case TurboFalcon.Repo.get(TurboFalcon.HackerNews.JobPosting, id) do
        nil -> {:error, :not_found}
        job_posting -> {:ok, job_posting}
      end

    {:reply, result, state}
  end

  def handle_call(:mark_dead_as_deleted, _from, state) do
    TurboFalcon.HackerNews.JobPosting
    |> where([jp], jp.text == "[dead]")
    |> TurboFalcon.Repo.update_all(set: [deleted: true])

    {:reply, :ok, state}
  end
end
