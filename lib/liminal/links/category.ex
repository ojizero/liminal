defmodule Liminal.Links.Category do
  use Liminal.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :expires_in_days, :integer, default: 30

    belongs_to :user, Liminal.Accounts.User
    has_many :link_categories, Liminal.Links.LinkCategory
    has_many :links, through: [:link_categories, :link]

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :expires_in_days])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> validate_number(:expires_in_days, greater_than: 0)
    |> unique_constraint(:name, name: :categories_user_id_name_index)
  end
end
