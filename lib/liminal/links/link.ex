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
    field :duration_seconds, :integer
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
    |> normalize_url()
    |> validate_required([:url])
    |> validate_length(:url, max: 2000)
    |> validate_url()
    |> validate_length(:title, max: 255)
    |> validate_length(:note, max: 500)
  end

  defp normalize_url(changeset) do
    case get_change(changeset, :url) do
      url when is_binary(url) -> put_change(changeset, :url, normalize_url_string(url))
      _ -> changeset
    end
  end

  defp normalize_url_string(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" -> trimmed
      Regex.match?(~r/^https?:\/\//i, trimmed) -> trimmed
      true -> "https://" <> trimmed
    end
  end

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      cond do
        url == "" -> []
        valid_url?(url) -> []
        true -> [url: "must be a valid URL"]
      end
    end)
  end

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        String.contains?(host, ".")

      _ ->
        false
    end
  end

  def metadata_changeset(link, attrs) do
    cast(link, attrs, [
      :title,
      :description,
      :favicon_url,
      :image_path,
      :duration_seconds,
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
