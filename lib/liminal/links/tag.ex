defmodule Liminal.Links.Tag do
  use Liminal.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    field :expires_in_days, :integer, default: 30

    belongs_to :user, Liminal.Accounts.User
    has_many :link_tags, Liminal.Links.LinkTag
    has_many :links, through: [:link_tags, :link]

    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :expires_in_days])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> validate_number(:expires_in_days, greater_than: 0)
    |> unique_constraint(:name, name: :tags_user_id_name_index)
  end
end
