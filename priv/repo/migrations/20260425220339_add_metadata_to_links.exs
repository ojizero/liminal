defmodule Liminal.Repo.Migrations.AddMetadataToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :description, :string
      add :favicon_url, :string
      add :indexed_at, :utc_datetime
    end
  end
end
