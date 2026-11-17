defmodule TurboFalcon.HackerNews.JobPosting do
  use Ecto.Schema
  import Ecto.Changeset
  alias TurboFalcon.HackerNews.JobPosting

  schema "job_postings" do
    field :item_id, :integer
    field :thread_id, :integer
    field :user, :string
    field :text, :string
    field :summarized, :boolean, default: false
    field :summarized_text, :string
    field :summarized_at, :utc_datetime
    field :timestamp, :utc_datetime
    field :deleted, :boolean, default: false
  end

  @doc false
  def changeset(%JobPosting{} = job_post, attrs) do
    attrs = normalize_timestamp(attrs)

    job_post
    |> cast(attrs, [
      :item_id,
      :thread_id,
      :user,
      :text,
      :summarized,
      :summarized_text,
      :summarized_at,
      :timestamp,
      :deleted
    ])
    |> validate_required([
      :item_id,
      :thread_id,
      :user,
      :text,
      :summarized
    ])
  end

  # HN sends Unix seconds; the column is a `:utc_datetime`. Both atom and
  # string keys are accepted, but only the atom key survives so `cast/3` never
  # sees a leftover string key. Out-of-range values are dropped rather than
  # raising.
  defp normalize_timestamp(attrs) do
    case attrs[:timestamp] || attrs["timestamp"] do
      ts when is_integer(ts) ->
        attrs = Map.delete(attrs, "timestamp")

        case DateTime.from_unix(ts) do
          {:ok, datetime} -> Map.put(attrs, :timestamp, datetime)
          {:error, _reason} -> Map.delete(attrs, :timestamp)
        end

      _ ->
        attrs
    end
  end
end
