defmodule TurboFalcon.HackerNews.JobThread do
  use Ecto.Schema
  import Ecto.Changeset
  alias TurboFalcon.HackerNews.JobThread

  schema "job_threads" do
    field :item_id, :integer
    field :title, :string
    field :created, :utc_datetime
    field :postings, :integer, default: 0
  end

  @doc false
  def changeset(%JobThread{} = job_thread, attrs) do
    attrs = normalize_created(attrs)

    job_thread
    |> cast(attrs, [:item_id, :title, :created, :postings])
    |> validate_required([:item_id, :title, :postings])
  end

  # See `JobPosting.normalize_timestamp/1`: same conversion, same key cleanup,
  # and out-of-range values are dropped instead of raising.
  defp normalize_created(attrs) do
    case attrs[:created] || attrs["created"] do
      ts when is_integer(ts) ->
        attrs = Map.delete(attrs, "created")

        case DateTime.from_unix(ts) do
          {:ok, datetime} -> Map.put(attrs, :created, datetime)
          {:error, _reason} -> Map.delete(attrs, :created)
        end

      _ ->
        attrs
    end
  end
end
