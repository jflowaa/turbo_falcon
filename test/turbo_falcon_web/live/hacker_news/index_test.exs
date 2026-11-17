defmodule TurboFalconWeb.Live.HackerNews.IndexTest do
  use TurboFalconWeb.ConnCase

  import Phoenix.LiveViewTest

  alias TurboFalcon.HackerNews.{JobPosting, JobThread}

  test "renders the empty state when there are no threads", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Hacker News Job Board"
    assert html =~ "No job postings found"
  end

  test "renders postings for the most recent thread", %{conn: conn} do
    thread = insert_thread()
    insert_posting(thread, %{text: "<p>We are hiring Elixir developers.</p>"})

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ thread.title
    assert view |> element("#job-postings") |> render() =~ "We are hiring Elixir developers."
  end

  test "sanitizes untrusted posting text before rendering", %{conn: conn} do
    thread = insert_thread()

    insert_posting(thread, %{
      text: ~s|<p>hello</p><script>alert(1)</script><img src=x onerror="alert(2)">|
    })

    {:ok, view, _html} = live(conn, ~p"/")
    html = view |> element("#job-postings") |> render()

    assert html =~ "hello"
    refute html =~ "<script"
    refute html =~ "onerror"
  end

  test "sanitizes stored summaries before rendering", %{conn: conn} do
    thread = insert_thread()

    insert_posting(thread, %{
      text: "<p>original</p>",
      summarized: true,
      summarized_text: ~s|<h2>Company</h2><p>Great job</p><script>alert(1)</script>|
    })

    {:ok, view, _html} = live(conn, ~p"/")
    html = view |> element("#job-postings") |> render()

    assert html =~ "Great job"
    refute html =~ "<script"
  end

  defp insert_thread do
    %JobThread{}
    |> JobThread.changeset(%{
      item_id: 9_999_999,
      title: "Ask HN: Who is hiring? (Test)",
      postings: 1
    })
    |> TurboFalcon.Repo.insert!()
  end

  defp insert_posting(thread, attrs) do
    %JobPosting{}
    |> JobPosting.changeset(
      Map.merge(
        %{
          item_id: System.unique_integer([:positive]),
          thread_id: thread.item_id,
          user: "someone",
          text: "text",
          summarized: false,
          timestamp: DateTime.utc_now()
        },
        attrs
      )
    )
    |> TurboFalcon.Repo.insert!()
  end
end
