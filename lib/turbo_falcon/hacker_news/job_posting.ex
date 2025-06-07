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
    attrs =
      case attrs["timestamp"] || attrs[:timestamp] do
        ts when is_integer(ts) ->
          {:ok, dt} = DateTime.from_unix(ts)
          Map.put(attrs, :timestamp, dt)

        _ ->
          attrs
      end

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
end
