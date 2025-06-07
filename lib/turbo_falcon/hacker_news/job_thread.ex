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
    attrs =
      case attrs["created"] || attrs[:created] do
        ts when is_integer(ts) ->
          {:ok, dt} = DateTime.from_unix(ts)
          Map.put(attrs, :created, dt)

        _ ->
          attrs
      end

    job_thread
    |> cast(attrs, [:item_id, :title, :created, :postings])
    |> validate_required([:item_id, :title, :postings])
  end
end
