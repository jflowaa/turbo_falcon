defmodule TurboFalconWeb.Live.HackerNews.JobThreadFormComponent do
  use Phoenix.Component

  # Usage: <.job_thread_form flash={@flash} job_threads={@job_threads} selected_thread_id={@selected_thread_id} filter={@filter} exclusive={@exclusive} />
  def job_thread_form(assigns) do
    ~H"""
    <div class="bg-card dark:bg-card-dark rounded-xl shadow p-6 flex flex-col gap-4 border border-border dark:border-border-dark">
      <form phx-change="select_job_thread">
        <div class="flex flex-col md:flex-row md:items-center gap-2">
          <label
            for="job_thread_select"
            class="font-semibold text-foreground dark:text-foreground-dark"
          >
            Select Job Thread:
          </label>
          <select
            id="job_thread_select"
            name="job_thread_item_id"
            class="rounded border-border dark:border-border-dark focus:border-accent dark:focus:border-accent-dark focus:ring-accent dark:focus:ring-accent-dark px-3 py-2 bg-background dark:bg-background-dark text-foreground dark:text-foreground-dark"
          >
            <%= for thread <- @job_threads do %>
              <option
                value={thread.item_id}
                selected={thread.item_id == @selected_thread_id}
                class="bg-card dark:bg-card-dark text-foreground dark:text-foreground-dark"
              >
                {thread.title}
              </option>
            <% end %>
          </select>
        </div>
      </form>

      <form phx-submit="filter_job_postings" class="flex flex-col gap-4">
        <input type="hidden" name="job_thread_item_id" value={@selected_thread_id} />
        <div class="flex flex-col md:flex-row md:items-center gap-2">
          <div class="flex flex-col flex-1">
            <label for="filter" class="font-semibold text-foreground dark:text-foreground-dark">
              Filter by terms:
            </label>
            <input
              type="text"
              id="filter"
              name="filter"
              value={@filter || ""}
              placeholder="Enter search terms (space separated, e.g. elixir dotnet c#)"
              autocomplete="off"
              class="rounded border-border dark:border-border-dark focus:border-accent dark:focus:border-accent-dark focus:ring-accent dark:focus:ring-accent-dark px-3 py-2 w-full bg-background dark:bg-background-dark text-foreground dark:text-foreground-dark"
            />
          </div>
        </div>
        <div class="flex items-center gap-2">
          <button
            type="submit"
            class="bg-accent dark:bg-accent-dark hover:bg-accent/80 dark:hover:bg-accent-dark/80 text-white font-semibold px-5 py-2 rounded shadow transition self-start"
          >
            Apply Filter
          </button>
          <label class="inline-flex items-center text-foreground dark:text-foreground-dark font-semibold ml-2">
            <input
              type="checkbox"
              name="exclusive"
              checked={@exclusive}
              class="rounded border-border dark:border-border-dark focus:ring-accent dark:focus:ring-accent-dark mr-2"
            /> Exclusive (AND all terms)
          </label>
        </div>
      </form>
    </div>
    """
  end
end
