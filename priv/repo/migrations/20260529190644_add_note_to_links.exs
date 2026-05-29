defmodule Liminal.Repo.Migrations.AddNoteToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :note, :text
    end
  end
end
