defmodule Mix.Tasks.TurboFalcon.ImportSqlite do
  @shortdoc "Import the legacy SQLite database into PostgreSQL"

  @moduledoc """
  One-time import of the legacy SQLite database into PostgreSQL.

  Run it after the target database has been created and migrated:

      mix db.migrate
      mix turbo_falcon.import_sqlite /path/to/turbo_falcon.db

  Pass `--truncate` to empty both tables and restart the id sequences before
  importing. Rows are inserted with their original ids and the id sequences are
  advanced past the highest imported id, so new rows do not collide.

  Requires the `sqlite3` command-line tool on the machine running the task. It
  reads the source database with `sqlite3 -json`; it never opens SQLite through
  Ecto.
  """

  use Mix.Task

  alias TurboFalcon.HackerNews.{JobPosting, JobThread}
  alias TurboFalcon.Repo

  @batch_size 500

  @impl Mix.Task
  def run(args) do
    {opts, paths, invalid} =
      OptionParser.parse(args, strict: [truncate: :boolean])

    if invalid != [] do
      Mix.raise("unknown options: #{inspect(invalid)}")
    end

    path =
      List.first(paths) ||
        Mix.raise("usage: mix turbo_falcon.import_sqlite <sqlite.db> [--truncate]")

    unless File.exists?(path) do
      Mix.raise("no such SQLite database: #{path}")
    end

    Application.put_env(:turbo_falcon, :start_pipeline, false)
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    if opts[:truncate] do
      Repo.query!("TRUNCATE job_postings, job_threads RESTART IDENTITY")
    end

    threads = read_rows(path, "job_threads") |> Enum.map(&thread_row/1)

    postings =
      path
      |> read_rows("job_postings")
      |> Enum.reject(&(&1["text"] in ["[dead]", "[flagged]"]))
      |> Enum.map(&posting_row/1)

    insert_all(JobThread, threads)
    insert_all(JobPosting, postings)

    reset_sequence("job_threads")
    reset_sequence("job_postings")

    Mix.shell().info(
      "Imported #{length(threads)} threads and #{length(postings)} postings from #{path}"
    )
  end

  defp read_rows(path, table) do
    case System.cmd("sqlite3", ["-json", path, "SELECT * FROM #{table}"], stderr_to_stdout: true) do
      {json, 0} ->
        Jason.decode!(json)

      {output, status} ->
        Mix.raise("sqlite3 failed reading #{table} (exit #{status}): #{output}")
    end
  end

  defp thread_row(row) do
    %{
      id: row["id"],
      item_id: row["item_id"],
      title: clean(row["title"]),
      created: parse_datetime(row["created"]),
      postings: row["postings"]
    }
  end

  defp posting_row(row) do
    %{
      id: row["id"],
      item_id: row["item_id"],
      thread_id: row["thread_id"],
      user: clean(row["user"]),
      text: clean(row["text"]),
      summarized: truthy?(row["summarized"]),
      summarized_text: clean(row["summarized_text"]),
      summarized_at: parse_datetime(row["summarized_at"]),
      timestamp: parse_datetime(row["timestamp"]),
      deleted: truthy?(row["deleted"])
    }
  end

  # The original SQLite columns are `boolean`, which SQLite stores as 0/1.
  defp truthy?(1), do: true
  defp truthy?("1"), do: true
  defp truthy?(true), do: true
  defp truthy?(_other), do: false

  # Ecto stored `:utc_datetime` as ISO 8601. Older data may have a space
  # separator instead of `T`.
  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(value) when is_binary(value) do
    with {:error, _} <- DateTime.from_iso8601(value),
         naive = String.replace(value, " ", "T"),
         {:ok, naive} <- NaiveDateTime.from_iso8601(naive) do
      DateTime.from_naive!(naive, "Etc/UTC")
    else
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  # PostgreSQL text cannot contain NUL bytes. HN content should not, but a
  # single bad row must not abort the import.
  defp clean(nil), do: nil
  defp clean(value) when is_binary(value), do: String.replace(value, <<0>>, "")

  defp insert_all(schema, rows) do
    rows
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(&Repo.insert_all(schema, &1, on_conflict: :nothing))
  end

  defp reset_sequence(table) do
    Repo.query!("""
    SELECT setval(
      pg_get_serial_sequence('#{table}', 'id'),
      COALESCE((SELECT MAX(id) FROM #{table}), 0) + 1,
      false
    )
    """)
  end
end
