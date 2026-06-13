defmodule Liminal.Repo.Migrations.AddDurationSecondsToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :duration_seconds, :integer
    end
  end
end
