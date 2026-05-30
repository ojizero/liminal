defmodule Liminal.Links.Link do
  use Liminal.Schema
  import Ecto.Changeset

  schema "links" do
    field :url, :string
    field :title, :string
    field :note, :string
    field :description, :string
    field :favicon_url, :string
    field :image_path, :string
    field :viewed_at, :utc_datetime
    field :indexed_at, :utc_datetime
    field :index_attempt_count, :integer, default: 0
    field :index_last_attempted_at, :utc_datetime
    field :index_next_attempt_at, :utc_datetime
    field :index_gave_up_at, :utc_datetime

    belongs_to :user, Liminal.Accounts.User
    has_many :link_tags, Liminal.Links.LinkTag
    has_many :tags, through: [:link_tags, :tag]

    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url, :title, :note])
    |> validate_required([:url])
    |> validate_length(:url, max: 2000)
    |> validate_length(:title, max: 255)
    |> validate_length(:note, max: 500)
  end

  def metadata_changeset(link, attrs) do
    cast(link, attrs, [
      :title,
      :description,
      :favicon_url,
      :image_path,
      :indexed_at,
      :index_attempt_count,
      :index_last_attempted_at,
      :index_next_attempt_at,
      :index_gave_up_at
    ])
  end

  def index_retry_changeset(link, attrs) do
    cast(link, attrs, [
      :index_attempt_count,
      :index_last_attempted_at,
      :index_next_attempt_at,
      :index_gave_up_at,
      :indexed_at
    ])
  end
end
