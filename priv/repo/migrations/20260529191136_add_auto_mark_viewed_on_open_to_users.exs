defmodule Liminal.Repo.Migrations.AddAutoMarkViewedOnOpenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :auto_mark_viewed_on_open, :boolean, null: false, default: false
    end
  end
end
