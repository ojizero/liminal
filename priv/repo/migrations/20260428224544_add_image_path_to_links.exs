defmodule Liminal.Repo.Migrations.AddImagePathToLinks do
  use Ecto.Migration

  def up do
    alter table(:links) do
      add :image_path, :string
    end

    # Reset indexed_at so Janitor re-indexes all links with image support
    execute "UPDATE links SET indexed_at = NULL"
  end

  def down do
    alter table(:links) do
      remove :image_path
    end
  end
end
