defmodule Liminal.Links.LinkCategory do
  use Liminal.Schema
  import Ecto.Changeset

  schema "link_categories" do
    field :expires_at, :utc_datetime

    belongs_to :link, Liminal.Links.Link
    belongs_to :category, Liminal.Links.Category

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(link_category, attrs) do
    link_category
    |> cast(attrs, [:expires_at])
    |> unique_constraint([:link_id, :category_id])
  end
end
