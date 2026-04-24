defmodule Liminal.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false
      add :expires_in_days, :integer, default: 30
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:user_id, :name])
    create index(:categories, [:user_id])
  end
end
