defmodule TurboFalcon.HackerNews.JobPostingsTest do
  use TurboFalcon.DataCase, async: false

  alias TurboFalcon.HackerNews.{JobPosting, JobPostings, JobThread}
  alias TurboFalcon.Repo

  setup do
    thread = insert_thread(1_000_001, "Ask HN: Who is hiring? (October 2026)")
    other_thread = insert_thread(1_000_002, "Ask HN: Who is hiring? (September 2026)")

    elixir =
      insert_posting(thread, %{
        item_id: 2_000_001,
        text: "Elixir and Phoenix",
        timestamp: ~U[2026-10-01 00:00:00Z]
      })

    remote =
      insert_posting(thread, %{
        item_id: 2_000_002,
        text: "Remote only, Elixir",
        timestamp: ~U[2026-10-02 00:00:00Z]
      })

    insert_posting(other_thread, %{item_id: 2_000_003, text: "Rust"})

    {:ok, thread: thread, other_thread: other_thread, elixir: elixir, remote: remote}
  end

  describe "threads/0 and latest_thread/0" do
    test "returns threads newest first" do
      assert [%JobThread{item_id: 1_000_002}, %JobThread{item_id: 1_000_001}] =
               JobPostings.threads()
    end

    test "returns nil when there are no threads" do
      Repo.delete_all(JobThread)

      assert JobPostings.threads() == []
      assert JobPostings.latest_thread() == nil
    end
  end

  describe "postings/3" do
    test "returns only the requested thread, newest first", %{
      thread: thread,
      elixir: elixir,
      remote: remote
    } do
      assert [%JobPosting{item_id: 2_000_002}, %JobPosting{item_id: 2_000_001}] =
               JobPostings.postings(thread.item_id)

      assert remote.timestamp >= elixir.timestamp
    end

    test "returns an empty list for a thread with no postings" do
      assert JobPostings.postings(999) == []
    end

    test "matches any filter by default", %{thread: thread} do
      assert [_, _] = JobPostings.postings(thread.item_id, ["elixir"])
      assert [%JobPosting{item_id: 2_000_001}] = JobPostings.postings(thread.item_id, ["phoenix"])
    end

    test "requires all filters when exclusive", %{thread: thread} do
      assert [%JobPosting{item_id: 2_000_002}] =
               JobPostings.postings(thread.item_id, ["elixir", "remote"], true)

      assert JobPostings.postings(thread.item_id, ["elixir", "rust"], true) == []
    end

    test "is case-insensitive", %{thread: thread} do
      assert [_, _] = JobPostings.postings(thread.item_id, ["ELIXIR"])
    end
  end

  describe "clear_summary/1 and get_posting/1" do
    test "clears the summary fields", %{elixir: elixir} do
      elixir
      |> JobPosting.changeset(%{
        summarized: true,
        summarized_text: "<p>summary</p>",
        summarized_at: DateTime.utc_now()
      })
      |> Repo.update!()

      assert JobPostings.clear_summary(elixir.id) == 1

      posting = JobPostings.get_posting(elixir.id)
      refute posting.summarized
      assert is_nil(posting.summarized_text)
      assert is_nil(posting.summarized_at)
    end

    test "returns nil for a missing posting" do
      assert JobPostings.get_posting(-1) == nil
      assert JobPostings.clear_summary(-1) == 0
    end
  end

  defp insert_thread(item_id, title) do
    %JobThread{}
    |> JobThread.changeset(%{item_id: item_id, title: title, postings: 1})
    |> Repo.insert!()
  end

  defp insert_posting(thread, attrs) do
    %JobPosting{}
    |> JobPosting.changeset(
      Map.merge(
        %{
          item_id: System.unique_integer([:positive]),
          thread_id: thread.item_id,
          user: "alice",
          text: "text",
          summarized: false,
          timestamp: DateTime.utc_now()
        },
        attrs
      )
    )
    |> Repo.insert!()
  end
end
