defmodule TurboFalcon.JobPostingWindow do
  @moduledoc """
  How long a job posting stays relevant.

  Ingestion and summarization have to agree on this: a posting is only worth
  refreshing (to pick up edits and deletions) while it can still be summarized.
  If the scheduler stops refreshing earlier than the producer stops
  summarizing, postings discovered in the gap are never updated again.

  The same window is also used as a proxy for "this thread is old and its
  postings are settled", which is what lets the scheduler skip unchanged old
  threads.
  """

  @days 30

  def days, do: @days

  def seconds, do: @days * 24 * 60 * 60

  @doc """
  The oldest timestamp that is still considered relevant.
  """
  def cutoff(now \\ DateTime.utc_now()), do: DateTime.add(now, -seconds(), :second)
end
