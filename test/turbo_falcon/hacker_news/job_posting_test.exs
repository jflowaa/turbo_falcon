defmodule TurboFalcon.HackerNews.JobPostingTest do
  use ExUnit.Case, async: true

  alias TurboFalcon.HackerNews.JobPosting

  @valid %{
    item_id: 1,
    thread_id: 2,
    user: "alice",
    text: "<p>Hi</p>",
    summarized: false
  }

  describe "changeset/2" do
    test "is valid with the required fields" do
      assert %{valid?: true} = JobPosting.changeset(%JobPosting{}, @valid)
    end

    test "defaults deleted to false" do
      changeset = JobPosting.changeset(%JobPosting{}, @valid)

      assert Ecto.Changeset.get_field(changeset, :deleted) == false
    end

    test "converts a Unix timestamp to a utc_datetime" do
      changeset = JobPosting.changeset(%JobPosting{}, Map.put(@valid, :timestamp, 1_700_000_000))

      assert changeset.changes.timestamp == ~U[2023-11-14 22:13:20Z]
    end

    test "accepts a string-keyed timestamp and removes the string key" do
      changeset = JobPosting.changeset(%JobPosting{}, Map.put(@valid, "timestamp", 1_700_000_000))

      assert changeset.changes.timestamp == ~U[2023-11-14 22:13:20Z]
      refute Map.has_key?(changeset.changes, "timestamp")
    end

    test "leaves a DateTime timestamp alone" do
      changeset =
        JobPosting.changeset(%JobPosting{}, Map.put(@valid, :timestamp, ~U[2026-01-01 00:00:00Z]))

      assert changeset.changes.timestamp == ~U[2026-01-01 00:00:00Z]
    end

    test "drops an out-of-range timestamp instead of raising" do
      changeset =
        JobPosting.changeset(%JobPosting{}, Map.put(@valid, :timestamp, 999_999_999_999_999))

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :timestamp)
    end

    test "requires item_id, thread_id, user and text" do
      changeset = JobPosting.changeset(%JobPosting{}, %{})

      refute changeset.valid?
      assert %{item_id: _, thread_id: _, user: _, text: _} = errors_on(changeset)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
