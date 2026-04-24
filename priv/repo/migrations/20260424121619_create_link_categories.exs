defmodule Liminal.Repo.Migrations.CreateLinkTags do
  use Ecto.Migration

  def change do
    create table(:link_tags) do
      add :link_id, references(:links, type: :binary_id, on_delete: :delete_all), null: false

      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), null: false

      add :expires_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:link_tags, [:link_id, :tag_id])
    create index(:link_tags, [:link_id])
    create index(:link_tags, [:tag_id])
  end
end
