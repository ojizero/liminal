defmodule Liminal.Schema do
  @moduledoc """
  Base schema module for all Liminal Ecto schemas.

  Configures UUID (`:binary_id`) as the default primary key and foreign key
  type app-wide. Use this instead of `use Ecto.Schema` in all schema modules:

      defmodule Liminal.MyResource do
        use Liminal.Schema

        schema "my_resources" do
          field :name, :string
          belongs_to :user, Liminal.Accounts.User
          timestamps(type: :utc_datetime)
        end
      end

  This sets the following module attributes automatically:

    * `@primary_key {:id, :binary_id, autogenerate: true}` — UUIDs auto-generated
      at the application layer on insert
    * `@foreign_key_type :binary_id` — `belongs_to` associations default to UUID
      foreign keys

  The corresponding migration-level defaults are configured in `config/config.exs`
  via `migration_primary_key` and `migration_foreign_key`.
  """

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
    end
  end
end
