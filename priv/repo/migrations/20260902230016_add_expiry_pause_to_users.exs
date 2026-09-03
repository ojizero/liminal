defmodule Liminal.Repo.Migrations.AddExpiryPauseToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :expiry_paused_at, :utc_datetime
      add :expiry_paused_until, :utc_datetime
    end

    create index(:users, [:expiry_paused_until])
  end
end
