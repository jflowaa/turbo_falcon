defmodule TurboFalcon.HackerNews.SchedulerTest.FakeClient do
  @moduledoc """
  In-memory stand-in for `TurboFalcon.HackerNews.WebApiClient`.

  State lives in an `Agent` so the tasks spawned by `Scheduler.run/1` can read
  it from their own processes. The registered pid is stashed in
  `:persistent_term` because the scheduler only accepts a client *module*.
  """

  @key {__MODULE__, :agent}

  def new, do: :fake_client

  def start(items, submitted) do
    {:ok, pid} = Agent.start_link(fn -> %{items: items, submitted: submitted, calls: []} end)
    :persistent_term.put(@key, pid)
    pid
  end

  def stop, do: :persistent_term.erase(@key)

  def calls, do: Agent.get(agent(), & &1.calls)

  def get_who_is_hiring_user(:fake_client) do
    Agent.get(agent(), fn state ->
      case state.submitted do
        {:error, reason} -> {:error, reason}
        submitted -> {:ok, %{status: 200, body: %{"submitted" => submitted}}}
      end
    end)
  end

  def get_item_by_id(:fake_client, id) do
    Agent.get_and_update(agent(), fn state ->
      result = Map.get(state.items, id, {:ok, %{status: 404, body: %{}}})
      {result, %{state | calls: [id | state.calls]}}
    end)
  end

  defp agent, do: :persistent_term.get(@key)
end

defmodule TurboFalcon.HackerNews.SchedulerTest do
  use TurboFalcon.DataCase, async: false

  alias TurboFalcon.HackerNews.{JobPosting, JobThread, Scheduler}
  alias TurboFalcon.HackerNews.SchedulerTest.FakeClient
  alias TurboFalcon.Repo

  @thread_id 1_000_001

  setup do
    on_exit(&FakeClient.stop/0)
    :ok
  end

  describe "run/1" do
    test "inserts the thread and its postings" do
      items = %{
        @thread_id => ok(thread_body(kids: [2_000_001, 2_000_002])),
        2_000_001 => ok(posting_body(2_000_001, "alice", "<p>We use Elixir.</p>")),
        2_000_002 => ok(posting_body(2_000_002, "bob", "<p>Remote only.</p>"))
      }

      FakeClient.start(items, [@thread_id])

      assert :ok = Scheduler.run(FakeClient)

      thread = Repo.get_by!(JobThread, item_id: @thread_id)
      assert thread.title == "Ask HN: Who is hiring? (October 2026)"
      assert thread.postings == 2

      postings = Repo.all(JobPosting)
      assert length(postings) == 2
      assert Enum.map(postings, & &1.user) |> Enum.sort() == ["alice", "bob"]
    end

    test "sanitizes posting text before storing it" do
      items = %{
        @thread_id => ok(thread_body(kids: [2_000_001])),
        2_000_001 =>
          ok(
            posting_body(
              2_000_001,
              "alice",
              ~s|<p>We use Elixir.</p><script>alert(1)</script><img src=x onerror="alert(2)">|
            )
          )
      }

      FakeClient.start(items, [@thread_id])

      assert :ok = Scheduler.run(FakeClient)

      posting = Repo.get_by!(JobPosting, item_id: 2_000_001)
      assert posting.text == "<p>We use Elixir.</p>"
    end

    test "broadcasts newly inserted postings" do
      items = %{
        @thread_id => ok(thread_body(kids: [2_000_001])),
        2_000_001 => ok(posting_body(2_000_001, "alice", "<p>Hi</p>"))
      }

      FakeClient.start(items, [@thread_id])
      Phoenix.PubSub.subscribe(TurboFalcon.PubSub, "job_postings:#{@thread_id}")

      assert :ok = Scheduler.run(FakeClient)

      assert_receive {:job_posting_updated, %JobPosting{item_id: 2_000_001}}
    end

    test "keeps processing when one thread cannot be fetched" do
      other_thread_id = @thread_id + 1

      items = %{
        @thread_id => {:error, :timeout},
        other_thread_id => ok(thread_body(item_id: other_thread_id, kids: [2_000_001])),
        2_000_001 =>
          ok(Map.put(posting_body(2_000_001, "alice", "<p>Hi</p>"), "parent", other_thread_id))
      }

      FakeClient.start(items, [@thread_id, other_thread_id])

      assert :ok = Scheduler.run(FakeClient)

      refute Repo.get_by(JobThread, item_id: @thread_id)
      assert Repo.get_by!(JobThread, item_id: other_thread_id)
      assert Repo.get_by!(JobPosting, item_id: 2_000_001)
    end

    test "keeps processing when one posting cannot be fetched" do
      items = %{
        @thread_id => ok(thread_body(kids: [2_000_001, 2_000_002])),
        2_000_001 => {:error, :econnrefused},
        2_000_002 => ok(posting_body(2_000_002, "bob", "<p>Hi</p>"))
      }

      FakeClient.start(items, [@thread_id])

      assert :ok = Scheduler.run(FakeClient)

      assert Repo.get_by!(JobPosting, item_id: 2_000_002)
      refute Repo.get_by(JobPosting, item_id: 2_000_001)
    end

    test "returns :ok when the whoishiring user cannot be fetched" do
      FakeClient.start(%{}, {:error, :timeout})

      assert :ok = Scheduler.run(FakeClient)
      assert Repo.all(JobThread) == []
    end

    test "ignores submissions that are not Who is hiring threads" do
      items = %{
        @thread_id => ok(thread_body(title: "Ask HN: Who wants to be hired? (October 2026)")),
        (@thread_id + 1) => ok(thread_body(item_id: @thread_id + 1, title: nil))
      }

      FakeClient.start(items, [@thread_id, @thread_id + 1])

      assert :ok = Scheduler.run(FakeClient)

      assert Repo.all(JobThread) == []
    end

    test "skips postings for old threads that have not changed" do
      old_thread =
        %JobThread{}
        |> JobThread.changeset(%{
          item_id: @thread_id,
          title: "Ask HN: Who is hiring? (January 2026)",
          created: ~U[2026-01-01 00:00:00Z],
          postings: 1
        })
        |> Repo.insert!()

      items = %{
        @thread_id =>
          ok(
            thread_body(
              kids: [2_000_001],
              time: DateTime.to_unix(~U[2026-01-01 00:00:00Z]),
              descendants: 1
            )
          )
      }

      FakeClient.start(items, [@thread_id])

      assert :ok = Scheduler.run(FakeClient)

      refute 2_000_001 in FakeClient.calls()
      assert Repo.all(JobPosting) == []
      assert Repo.get!(JobThread, old_thread.id).postings == 1
    end

    test "marks a posting as deleted when HN reports it without an author" do
      insert_posting(%{item_id: 2_000_001, text: "<p>Hi</p>"})

      items = %{
        @thread_id => ok(thread_body(kids: [2_000_001])),
        2_000_001 => ok(%{"id" => 2_000_001, "deleted" => true, "time" => now()})
      }

      FakeClient.start(items, [@thread_id])

      assert :ok = Scheduler.run(FakeClient)

      assert Repo.get_by!(JobPosting, item_id: 2_000_001).deleted
    end

    test "does not insert placeholder postings" do
      for {placeholder, index} <- Enum.with_index(["[dead]", "[flagged]"]) do
        item_id = 2_000_001 + index

        items = %{
          @thread_id => ok(thread_body(kids: [item_id])),
          item_id => ok(posting_body(item_id, "alice", placeholder))
        }

        FakeClient.start(items, [@thread_id])

        assert :ok = Scheduler.run(FakeClient)
        refute Repo.get_by(JobPosting, item_id: item_id)
      end
    end

    test "treats the dead flag as deleted even when the author is present" do
      insert_posting(%{item_id: 2_000_001, text: "<p>Hi</p>"})

      body = Map.put(posting_body(2_000_001, "alice", "[dead]"), "dead", true)

      items = %{
        @thread_id => ok(thread_body(kids: [2_000_001])),
        2_000_001 => ok(body)
      }

      FakeClient.start(items, [@thread_id])

      assert :ok = Scheduler.run(FakeClient)

      posting = Repo.get_by!(JobPosting, item_id: 2_000_001)
      assert posting.deleted
      assert posting.text == "<p>Hi</p>"
    end

    test "keeps legitimate bracket text" do
      items = %{
        @thread_id => ok(thread_body(kids: [2_000_001])),
        2_000_001 => ok(posting_body(2_000_001, "alice", "[POSITION FILLED] thanks!"))
      }

      FakeClient.start(items, [@thread_id])

      assert :ok = Scheduler.run(FakeClient)

      assert Repo.get_by!(JobPosting, item_id: 2_000_001).text == "[POSITION FILLED] thanks!"
    end

    test "skips postings with no text instead of failing the insert" do
      items = %{
        @thread_id => ok(thread_body(kids: [2_000_001])),
        2_000_001 =>
          ok(%{"id" => 2_000_001, "parent" => @thread_id, "by" => "alice", "time" => now()})
      }

      FakeClient.start(items, [@thread_id])

      assert :ok = Scheduler.run(FakeClient)
      refute Repo.get_by(JobPosting, item_id: 2_000_001)
    end
  end

  defp insert_posting(attrs) do
    insert_thread()

    %JobPosting{}
    |> JobPosting.changeset(
      Map.merge(
        %{
          item_id: 2_000_001,
          thread_id: @thread_id,
          user: "alice",
          text: "<p>Hi</p>",
          summarized: false
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp insert_thread do
    %JobThread{}
    |> JobThread.changeset(%{
      item_id: @thread_id,
      title: "Ask HN: Who is hiring? (October 2026)",
      postings: 1
    })
    |> Repo.insert!()
  end

  defp ok(body), do: {:ok, %{status: 200, body: body}}

  defp now, do: DateTime.utc_now() |> DateTime.to_unix()

  defp thread_body(opts) do
    kids = Keyword.get(opts, :kids, [])

    %{
      "id" => Keyword.get(opts, :item_id, @thread_id),
      "title" => Keyword.get(opts, :title, "Ask HN: Who is hiring? (October 2026)"),
      "time" => Keyword.get(opts, :time, now()),
      "descendants" => Keyword.get(opts, :descendants, length(kids)),
      "kids" => kids
    }
  end

  defp posting_body(item_id, user, text) do
    %{
      "id" => item_id,
      "parent" => @thread_id,
      "by" => user,
      "text" => text,
      "time" => now(),
      "deleted" => false
    }
  end
end
