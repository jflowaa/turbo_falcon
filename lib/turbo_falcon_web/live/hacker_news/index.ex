defmodule TurboFalconWeb.Live.HackerNews.Index do
  use TurboFalconWeb, :live_view

  alias TurboFalcon.HackerNews.JobPostings
  import TurboFalconWeb.Live.HackerNews.JobPostingCardComponent
  import TurboFalconWeb.Live.HackerNews.JobThreadFormComponent

  @impl true
  def mount(_params, _session, socket) do
    socket = socket |> assign(:filter, "") |> assign(:exclusive, false)

    socket =
      if connected?(socket) do
        load_job_threads(socket)
      else
        socket |> assign(:job_threads, []) |> assign(:job_postings_empty, true)
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, load_job_threads(socket)}

  @impl true
  def handle_event("select_job_thread", %{"job_thread_item_id" => item_id}, socket) do
    with {:ok, thread_id} <- parse_id(item_id) do
      postings = JobPostings.postings(thread_id)

      {:noreply,
       socket
       |> assign(:selected_thread_id, thread_id)
       |> assign(:job_postings_empty, postings == [])
       |> stream(:job_postings, postings, reset: true)
       |> subscribe_to_thread(thread_id)}
    else
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "filter_job_postings",
        %{"filter" => filter, "job_thread_item_id" => item_id} = params,
        socket
      ) do
    with {:ok, thread_id} <- parse_id(item_id) do
      filters = filter |> String.split(~r/\s+/, trim: true) |> Enum.reject(&(&1 == ""))
      exclusive? = Map.has_key?(params, "exclusive")
      postings = JobPostings.postings(thread_id, filters, exclusive?)

      {:noreply,
       socket
       |> assign(:filter, filter)
       |> assign(:exclusive, exclusive?)
       |> assign(:selected_thread_id, thread_id)
       |> assign(:job_postings_empty, postings == [])
       |> stream(:job_postings, postings, reset: true)}
    else
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_summary", %{"id" => id}, socket) do
    with {:ok, posting_id} <- parse_id(id),
         %{} = posting <- JobPostings.get_posting(posting_id) do
      JobPostings.clear_summary(posting_id)

      posting = %{posting | summarized: false, summarized_text: nil, summarized_at: nil}

      Phoenix.PubSub.broadcast(
        TurboFalcon.PubSub,
        topic(posting.thread_id),
        {:job_posting_updated, posting}
      )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:job_posting_updated, posting}, socket) do
    if posting.thread_id == socket.assigns[:selected_thread_id] do
      {:noreply, stream_insert(socket, :job_postings, posting)}
    else
      {:noreply, socket}
    end
  end

  defp load_job_threads(socket) do
    case JobPostings.threads() do
      [first_thread | _] = job_threads ->
        postings = JobPostings.postings(first_thread.item_id)

        socket
        |> assign(:job_threads, job_threads)
        |> assign(:selected_thread_id, first_thread.item_id)
        |> assign(:job_postings_empty, postings == [])
        |> stream(:job_postings, postings, reset: true)
        |> subscribe_to_thread(first_thread.item_id)

      [] ->
        socket
        |> assign(:job_threads, [])
        |> assign(:selected_thread_id, nil)
        |> assign(:job_postings_empty, true)
        |> stream(:job_postings, [], reset: true)
    end
  end

  # Subscribing is idempotent per thread: `mount/3` and `handle_params/3` both
  # load, and without the guard the LiveView would handle every update twice.
  defp subscribe_to_thread(socket, thread_id) do
    if connected?(socket) and socket.assigns[:subscribed_thread_id] != thread_id do
      if previous = socket.assigns[:subscribed_thread_id] do
        Phoenix.PubSub.unsubscribe(TurboFalcon.PubSub, topic(previous))
      end

      Phoenix.PubSub.subscribe(TurboFalcon.PubSub, topic(thread_id))
      assign(socket, :subscribed_thread_id, thread_id)
    else
      socket
    end
  end

  defp topic(thread_id), do: "job_postings:#{thread_id}"

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end
end
