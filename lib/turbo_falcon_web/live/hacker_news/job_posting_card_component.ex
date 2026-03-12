defmodule TurboFalconWeb.Live.HackerNews.JobPostingCardComponent do
  use Phoenix.Component

  # Usage: <.job_posting_card dom_id={dom_id} job_posting={job_posting} />
  def job_posting_card(assigns) do
    ~H"""
    <div
      id={@dom_id}
      class={[
        "relative bg-card dark:bg-card-dark rounded-xl shadow-md p-4 mt-2 transition border border-border dark:border-border-dark",
        @job_posting.deleted &&
          "border-2 border-error dark:border-error-dark bg-error/10 dark:bg-error-dark/10 opacity-70"
      ]}
    >
      <%= if @job_posting.deleted do %>
        <div class="absolute top-3 right-3 bg-error dark:bg-error-dark text-white text-xs font-bold px-3 py-1 rounded-full shadow">
          DELETED
        </div>
      <% end %>

      <div
        id={"summary-toggle-" <> to_string(@job_posting.id)}
        data-summary-toggle-container
        phx-hook="SummaryToggle"
      >
        <%= if @job_posting.summarized_text do %>
          {render_text_block(@job_posting.summarized_text,
            summary: true,
            style: if(@job_posting.summarized, do: "", else: "display:none;")
          )}
          {render_text_block(@job_posting.text,
            original: true,
            style: if(@job_posting.summarized, do: "display:none;", else: "")
          )}
          <button
            type="button"
            data-toggle-summary
            class="mt-2 text-accent dark:text-accent-dark hover:underline text-sm"
          >
            <span data-toggle-label>
              {if @job_posting.summarized, do: "Show original", else: "Show summary"}
            </span>
          </button>
        <% else %>
          {render_text_block(@job_posting.text, original: true)}
        <% end %>
      </div>

      <div class="mt-4 text-foreground dark:text-foreground-dark text-xs flex items-center gap-2">
        <span>
          Posted by
          <a
            href={"https://news.ycombinator.com/user?id=" <> @job_posting.user}
            target="_blank"
            rel="noopener"
            class="font-semibold text-accent dark:text-accent-dark hover:underline dark:hover:text-white focus:outline-none focus:ring-2 focus:ring-accent dark:focus:ring-accent-dark focus:ring-offset-2"
          >
            {@job_posting.user}
          </a>
        </span>
        <span>&bull;</span>
        <span
          id={"timestamp-" <> to_string(@job_posting.id)}
          data-utc={@job_posting.timestamp}
          title={@job_posting.timestamp}
          phx-hook="LocalTimeTooltip"
          class="cursor-pointer underline decoration-dotted decoration-1"
        >
          <span data-localtime>{@job_posting.timestamp}</span>
        </span>
        <span>&bull;</span>
        <span>
          <a
            href={"https://news.ycombinator.com/item?id=" <> to_string(@job_posting.item_id)}
            target="_blank"
            rel="noopener"
            class="font-semibold text-accent dark:text-accent-dark hover:underline dark:hover:text-white focus:outline-none focus:ring-2 focus:ring-accent dark:focus:ring-accent-dark focus:ring-offset-2"
          >
            See on Hacker News
          </a>
        </span>
        <span>&bull;</span>
        <%= if @job_posting.summarized_text do %>
          <button
            type="button"
            phx-click="clear_summary"
            phx-value-id={@job_posting.id}
            class="ml-2 px-2 py-1 rounded bg-warning dark:bg-warning-dark text-warning-dark dark:text-zinc-900 border border-warning dark:border-warning-dark hover:bg-warning/80 dark:hover:bg-warning-dark/80 transition font-semibold shadow-sm"
          >
            Re-summarize
          </button>
        <% else %>
          <span class="ml-2 px-2 py-1 rounded bg-success dark:bg-success-dark text-success-dark dark:text-zinc-900 border border-success dark:border-success-dark font-semibold shadow-sm">
            Summarize Pending
          </span>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_text_block(text, opts) do
    assigns = %{text: text, opts: opts}

    ~H"""
    <div
      class="prose prose-sm prose-slate prose-headings:text-inherit prose-strong:text-inherit prose-blockquote:text-inherit prose-p:my-1 prose-headings:my-2 prose-ul:my-1 prose-ol:my-1 prose-li:my-0.5 max-w-none text-foreground dark:text-foreground-dark [&_a]:text-accent [&_a]:hover:underline dark:[&_a]:text-white dark:[&_a]:hover:text-accent-dark [&_li::marker]:text-inherit"
      data-summary={@opts[:summary]}
      data-original={@opts[:original]}
      style={@opts[:style]}
    >
      {Phoenix.HTML.raw(@text || "")}
    </div>
    """
  end
end
