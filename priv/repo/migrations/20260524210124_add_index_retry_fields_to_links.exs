defmodule Liminal.Repo.Migrations.AddIndexRetryFieldsToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :index_attempt_count, :integer, null: false, default: 0
      add :index_last_attempted_at, :utc_datetime
      add :index_next_attempt_at, :utc_datetime
      add :index_gave_up_at, :utc_datetime
    end

    create index(:links, [:indexed_at, :index_gave_up_at, :index_next_attempt_at])
  end
end
