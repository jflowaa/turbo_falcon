defmodule TurboFalcon.Repo.Migrations.Initial do
  use Ecto.Migration

  def change do
    create table(:job_threads) do
      add :item_id, :integer
      add :title, :string
      add :created, :utc_datetime
      add :postings, :integer, default: 0
    end

    create unique_index(:job_threads, [:item_id])

    create table(:job_postings) do
      add :item_id, :integer
      add :thread_id, :integer
      add :user, :string
      add :text, :string
      add :summarized, :boolean, default: false
      add :summarized_text, :string
      add :summarized_at, :utc_datetime
      add :timestamp, :utc_datetime
      add :deleted, :boolean, default: false
    end

    create unique_index(:job_postings, [:item_id])
    create index(:job_postings, [:thread_id])
  end
end
