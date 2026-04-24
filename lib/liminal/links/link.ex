defmodule Liminal.Links.Link do
  use Ecto.Schema
  import Ecto.Changeset

  schema "links" do
    field :url, :string
    field :title, :string
    field :viewed_at, :utc_datetime

    belongs_to :user, Liminal.Accounts.User
    has_many :link_categories, Liminal.Links.LinkCategory
    has_many :categories, through: [:link_categories, :category]

    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url, :title])
    |> validate_required([:url])
    |> validate_length(:url, max: 2000)
    |> validate_length(:title, max: 255)
  end
end
