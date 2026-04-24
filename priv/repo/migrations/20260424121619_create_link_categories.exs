defmodule Liminal.Repo.Migrations.CreateLinkCategories do
  use Ecto.Migration

  def change do
    create table(:link_categories) do
      add :link_id, references(:links, type: :binary_id, on_delete: :delete_all), null: false

      add :category_id, references(:categories, type: :binary_id, on_delete: :delete_all),
        null: false

      add :expires_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:link_categories, [:link_id, :category_id])
    create index(:link_categories, [:link_id])
    create index(:link_categories, [:category_id])
  end
end
