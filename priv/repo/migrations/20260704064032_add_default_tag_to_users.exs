defmodule Liminal.Repo.Migrations.AddDefaultTagToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :default_tags_enabled, :boolean, null: false, default: false
      add :default_tag_id, references(:tags, on_delete: :nilify_all)
    end
  end
end
