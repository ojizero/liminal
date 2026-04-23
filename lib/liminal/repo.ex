defmodule Liminal.Repo do
  use Ecto.Repo,
    otp_app: :liminal,
    adapter: Ecto.Adapters.SQLite3
end
