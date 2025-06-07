defmodule TurboFalconWeb.Live.HackerNews.Index do
  use TurboFalconWeb, :live_view
  alias TurboFalcon.HackerNews.JobServer
  import TurboFalconWeb.Live.HackerNews.JobPostingCardComponent
  import TurboFalconWeb.Live.HackerNews.JobThreadFormComponent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok,
       load_job_threads(socket)
       |> assign(:filter, "")
       |> assign(:exclusive, false)}
    else
      {:ok,
       socket |> assign(:job_threads, []) |> assign(:filter, "") |> assign(:exclusive, false)}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, load_job_threads(socket)}
  end

  @impl true
  def handle_event("toggle_summary", %{"id" => id}, socket) do
    postings =
      Enum.map(
        socket.assigns.streams.job_postings,
        fn {dom_id, posting} ->
          if posting.id == String.to_integer(id) do
            {dom_id, %{posting | summarized: !posting.summarized}}
          else
            {dom_id, posting}
          end
        end
      )

    {:noreply, assign(socket, streams: %{job_postings: postings})}
  end

  @impl true
  def handle_event("select_job_thread", %{"job_thread_item_id" => item_id}, socket) do
    if socket.assigns[:selected_thread_id] do
      Phoenix.PubSub.unsubscribe(
        TurboFalcon.PubSub,
        "job_postings:#{socket.assigns.selected_thread_id}"
      )
    end

    Phoenix.PubSub.subscribe(TurboFalcon.PubSub, "job_postings:#{item_id}")

    {:ok, job_postings} =
      JobServer.get_job_postings(String.to_integer(item_id))

    socket =
      socket
      |> assign(:selected_thread_id, String.to_integer(item_id))
      |> assign(:job_postings_empty, job_postings == [])
      |> stream(:job_postings, job_postings, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "filter_job_postings",
        %{"filter" => filter, "job_thread_item_id" => item_id} = params,
        socket
      ) do
    filters =
      filter
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reject(&(&1 == ""))

    is_exclusive = Map.has_key?(params, "exclusive")

    case JobServer.get_job_postings(
           String.to_integer(item_id),
           filters,
           Map.has_key?(params, "exclusive")
         ) do
      {:ok, job_postings} ->
        socket =
          socket
          |> assign(:filter, filter)
          |> assign(:exclusive, is_exclusive)
          |> assign(:selected_thread_id, String.to_integer(item_id))
          |> assign(:job_postings_empty, job_postings == [])
          |> stream(:job_postings, job_postings, reset: true)

        {:noreply, socket}

      {:error, _reason} ->
        IO.puts("empty job postings")

        {:noreply,
         socket |> assign(:job_postings_empty, true) |> stream(:job_postings, [], reset: true)}
    end
  end

  @impl true
  def handle_event("clear_summary", %{"id" => id}, socket) do
    {:ok, _} = JobServer.clear_summary(String.to_integer(id))
    {:ok, job_posting} = JobServer.get_job_posting(String.to_integer(id))

    Phoenix.PubSub.broadcast(
      TurboFalcon.PubSub,
      "job_postings:#{socket.assigns.selected_thread_id}",
      {:job_posting_updated, job_posting}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:job_posting_updated, posting}, socket) do
    if posting.thread_id == socket.assigns.selected_thread_id do
      {:noreply, stream_insert(socket, :job_postings, posting)}
    else
      {:noreply, socket}
    end
  end

  defp load_job_threads(socket) do
    case JobServer.get_job_threads() do
      {:ok, [first_thread | _] = job_threads} ->
        postings =
          case JobServer.get_job_postings(first_thread.item_id) do
            {:ok, job_postings} -> job_postings
            _ -> []
          end

        Phoenix.PubSub.subscribe(TurboFalcon.PubSub, "job_postings:#{first_thread.item_id}")

        socket
        |> assign(:job_threads, job_threads)
        |> assign(:selected_thread_id, first_thread.item_id)
        |> stream(:job_postings, postings, reset: true)
        |> assign(:job_postings_empty, postings == [])

      {:ok, []} ->
        socket
        |> assign(:job_threads, [])
        |> assign(:selected_thread_id, nil)
        |> assign(:job_postings_empty, true)
        |> stream(:job_postings, [], reset: true)

      {:error, reason} ->
        socket
        |> assign(:error, reason)
        |> assign(:job_threads, [])
        |> assign(:selected_thread_id, nil)
        |> assign(:job_postings_empty, true)
        |> stream(:job_postings, [], reset: true)
    end
  end
end
