defmodule Liminal.Repo.Migrations.RenameEmailToUsername do
  use Ecto.Migration

  def change do
    rename table(:users), :email, to: :username

    drop index(:users, [:email])
    create unique_index(:users, [:username])

    alter table(:users_tokens) do
      remove :sent_to, :string
    end
  end
end
