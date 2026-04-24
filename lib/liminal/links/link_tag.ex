defmodule Liminal.Links.LinkTag do
  use Liminal.Schema
  import Ecto.Changeset

  schema "link_tags" do
    field :expires_at, :utc_datetime

    belongs_to :link, Liminal.Links.Link
    belongs_to :tag, Liminal.Links.Tag

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(link_tag, attrs) do
    link_tag
    |> cast(attrs, [:expires_at])
    |> unique_constraint([:link_id, :tag_id])
  end
end
