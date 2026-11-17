defmodule TurboFalcon.HackerNews.JobThreadTest do
  use ExUnit.Case, async: true

  alias TurboFalcon.HackerNews.JobThread

  @valid %{item_id: 1, title: "Ask HN: Who is hiring? (October 2026)", postings: 3}

  describe "changeset/2" do
    test "is valid with the required fields" do
      assert %{valid?: true} = JobThread.changeset(%JobThread{}, @valid)
    end

    test "converts a Unix created timestamp to a utc_datetime" do
      changeset = JobThread.changeset(%JobThread{}, Map.put(@valid, :created, 1_700_000_000))

      assert changeset.changes.created == ~U[2023-11-14 22:13:20Z]
    end

    test "accepts a string-keyed created timestamp and removes the string key" do
      changeset = JobThread.changeset(%JobThread{}, Map.put(@valid, "created", 1_700_000_000))

      assert changeset.changes.created == ~U[2023-11-14 22:13:20Z]
      refute Map.has_key?(changeset.changes, "created")
    end

    test "drops an out-of-range created timestamp instead of raising" do
      changeset =
        JobThread.changeset(%JobThread{}, Map.put(@valid, :created, 999_999_999_999_999))

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :created)
    end

    test "requires item_id and title" do
      changeset = JobThread.changeset(%JobThread{}, %{})

      refute changeset.valid?
      assert %{item_id: _, title: _} = errors_on(changeset)
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
