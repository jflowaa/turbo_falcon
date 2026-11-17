defmodule TurboFalcon.JobPostingSummarizing.ConsumerTest.FakeClient do
  @moduledoc """
  Canned-response LLM client.

  `handle_events/3` summarizes inline in the caller's process, so the responses
  live in the process dictionary and no extra process is needed.
  """

  def new, do: :client

  def put_response(text, response) do
    Process.put({__MODULE__, text}, response)
  end

  def get_summary_of_job_posting(:client, text) do
    Process.get({__MODULE__, text}, {:error, :no_canned_response})
  end
end

defmodule TurboFalcon.JobPostingSummarizing.ConsumerTest do
  use TurboFalcon.DataCase, async: false

  alias TurboFalcon.HackerNews.{JobPosting, JobThread}
  alias TurboFalcon.JobPostingSummarizing.Consumer
  alias TurboFalcon.JobPostingSummarizing.ConsumerTest.FakeClient
  alias TurboFalcon.Repo

  @text "<p>We are hiring Elixir developers.</p>"

  setup do
    thread =
      %JobThread{}
      |> JobThread.changeset(%{
        item_id: 1_000_001,
        title: "Ask HN: Who is hiring? (October 2026)",
        postings: 1
      })
      |> Repo.insert!()

    posting =
      %JobPosting{}
      |> JobPosting.changeset(%{
        item_id: 2_000_001,
        thread_id: thread.item_id,
        user: "alice",
        text: @text,
        summarized: false
      })
      |> Repo.insert!()

    {:ok, posting: posting}
  end

  describe "handle_events/3" do
    test "stores an OpenAI-shaped summary", %{posting: posting} do
      FakeClient.put_response(
        @text,
        {:ok, response(openai_body("<h2>Company</h2><p>Elixir</p>"))}
      )

      assert {:noreply, [], _state} = handle_events(posting)

      posting = Repo.reload!(posting)
      assert posting.summarized
      assert posting.summarized_text == "<h2>Company</h2><p>Elixir</p>"
      assert posting.summarized_at
    end

    test "stores a Gemini-shaped summary", %{posting: posting} do
      FakeClient.put_response(@text, {:ok, response(gemini_body("<p>Gemini summary</p>"))})

      assert {:noreply, [], _state} = handle_events(posting)

      assert Repo.reload!(posting).summarized_text == "<p>Gemini summary</p>"
    end

    test "sanitizes the summary before storing it", %{posting: posting} do
      body = openai_body(~s|<p>Great job</p><script>alert(1)</script>|)
      FakeClient.put_response(@text, {:ok, response(body)})

      assert {:noreply, [], _state} = handle_events(posting)

      assert Repo.reload!(posting).summarized_text == "<p>Great job</p>"
    end

    test "does not mark an unknown response shape as summarized", %{posting: posting} do
      FakeClient.put_response(@text, {:ok, response(%{"unexpected" => "shape"})})

      assert {:noreply, [], _state} = handle_events(posting)

      posting = Repo.reload!(posting)
      refute posting.summarized
      assert is_nil(posting.summarized_text)
    end

    test "does not mark an empty completion as summarized", %{posting: posting} do
      FakeClient.put_response(@text, {:ok, response(openai_body(""))})

      assert {:noreply, [], _state} = handle_events(posting)

      posting = Repo.reload!(posting)
      refute posting.summarized
      assert is_nil(posting.summarized_text)
    end

    test "does not mark a whitespace-only completion as summarized", %{posting: posting} do
      FakeClient.put_response(@text, {:ok, response(openai_body("```html\n\n```"))})

      assert {:noreply, [], _state} = handle_events(posting)

      refute Repo.reload!(posting).summarized
    end

    test "strips fences with any language tag", %{posting: posting} do
      for tag <- ["```html", "```HTML", "```", "```text"] do
        FakeClient.put_response(
          @text,
          {:ok, response(openai_body("#{tag}\n<p>Fenced</p>\n```"))}
        )

        assert {:noreply, [], _state} = handle_events(posting)
        assert Repo.reload!(posting).summarized_text == "<p>Fenced</p>"
      end
    end

    test "pauses instead of storing on a 429", %{posting: posting} do
      FakeClient.put_response(@text, {:ok, %{status: 429, body: %{}}})

      assert {:noreply, [], %{paused: false}} = handle_events(posting)
      assert_received :pause_for_rate_limit

      posting = Repo.reload!(posting)
      refute posting.summarized
      assert is_nil(posting.summarized_text)
    end

    test "does not store on an unexpected status", %{posting: posting} do
      FakeClient.put_response(@text, {:ok, %{status: 500, body: %{}}})

      assert {:noreply, [], _state} = handle_events(posting)

      refute Repo.reload!(posting).summarized
    end

    test "does not store when the client errors", %{posting: posting} do
      FakeClient.put_response(@text, {:error, :timeout})

      assert {:noreply, [], _state} = handle_events(posting)

      refute Repo.reload!(posting).summarized
    end
  end

  defp handle_events(posting) do
    Consumer.handle_events(
      [posting],
      nil,
      %{api_client_module: FakeClient, api_client: :client, paused: false, subscription: nil}
    )
  end

  defp response(body), do: %{status: 200, body: body}

  defp openai_body(content) do
    %{"choices" => [%{"message" => %{"content" => content}}]}
  end

  defp gemini_body(text) do
    %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text}]}}]}
  end
end
