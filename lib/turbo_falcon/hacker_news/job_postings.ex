defmodule TurboFalcon.HackerNews.JobPostings do
  @moduledoc """
  Read-side queries for the job board.

  Returns plain lists: an empty result is `[]`, not `{:error, "No ... found"}`.
  A missing row is `nil`.
  """

  import Ecto.Query

  alias TurboFalcon.HackerNews.{JobPosting, JobThread}
  alias TurboFalcon.Repo

  def threads, do: Repo.all(from jt in JobThread, order_by: [desc: jt.item_id])

  def latest_thread, do: Repo.one(from jt in JobThread, order_by: [desc: jt.item_id], limit: 1)

  def postings(thread_id, filters \\ [], exclusive? \\ false) do
    JobPosting
    |> where([jp], jp.thread_id == ^thread_id)
    |> filter_by(filters, exclusive?)
    |> order_by([jp], desc: jp.timestamp)
    |> Repo.all()
  end

  def get_posting(id), do: Repo.get(JobPosting, id)

  @doc """
  Clears the summary so the producer picks the posting up again.
  """
  def clear_summary(id) do
    {count, _} =
      JobPosting
      |> where([jp], jp.id == ^id)
      |> Repo.update_all(set: [summarized: false, summarized_text: nil, summarized_at: nil])

    count
  end

  defp filter_by(query, [], _exclusive?), do: query

  defp filter_by(query, filters, exclusive?) do
    where(query, ^combine(filters, exclusive?))
  end

  defp combine([first | rest], exclusive?) do
    Enum.reduce(rest, like_filter(first), fn filter, acc ->
      if exclusive? do
        dynamic([jp], ^acc and ^like_filter(filter))
      else
        dynamic([jp], ^acc or ^like_filter(filter))
      end
    end)
  end

  defp like_filter(filter) do
    dynamic([jp], like(fragment("LOWER(?)", jp.text), ^("%" <> String.downcase(filter) <> "%")))
  end
end
