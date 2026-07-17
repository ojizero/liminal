defmodule Liminal.Links.Query do
  @moduledoc """
  Read queries for links and link filters.
  """

  import Ecto.Query

  alias Liminal.Links.{Link, LinkTag, TextSearch}
  alias Liminal.Repo

  @doc """
  Lists links for the given user with preloaded tags.

  ## Options

    * `:filter` - `:unviewed` (default), `:all`, or `:viewed`
    * `:sort` - `:time_added_desc` (default), `:time_added_asc`, or `:expiring_soon`
    * `:tag_ids` - list of tag IDs to filter by (default `[]` = no tag filter)
    * `:query` - fuzzy text search across title, note, description, and URL (default `""`)

  """
  def list_links(scope, opts \\ []) do
    filter = Keyword.get(opts, :filter, :unviewed)
    sort = Keyword.get(opts, :sort, :time_added_desc)
    tag_ids = Keyword.get(opts, :tag_ids, [])
    query = Keyword.get(opts, :query, "")

    from(l in Link, where: l.user_id == ^scope.user.id)
    |> apply_link_filter(filter)
    |> apply_tag_filter(tag_ids)
    |> apply_sort(sort)
    |> Repo.all()
    |> Repo.preload(link_tags: :tag)
    |> TextSearch.filter_links(query)
  end

  @doc """
  Returns a random link for the given user.

  Picks uniformly from all saved links regardless of viewed state or tags.
  """
  def random_link(scope) do
    case from(l in Link,
           where: l.user_id == ^scope.user.id,
           order_by: fragment("RANDOM()"),
           limit: 1
         )
         |> Repo.one() do
      nil -> {:error, :no_links}
      link -> {:ok, Repo.preload(link, link_tags: :tag)}
    end
  end

  @doc "Fetches a user's link by id with tags preloaded; raises when missing."
  def get_link!(scope, id) do
    Repo.get_by!(Link, id: id, user_id: scope.user.id)
    |> Repo.preload(link_tags: :tag)
  end

  @doc "Finds a user's link by exact URL, or `nil` if none exists."
  def find_link_by_url(scope, url) when is_binary(url) do
    from(l in Link,
      where: l.user_id == ^scope.user.id and l.url == ^url,
      preload: [link_tags: :tag]
    )
    |> Repo.one()
  end

  def apply_link_filter(query, :unviewed) do
    from(l in query, where: is_nil(l.viewed_at))
  end

  def apply_link_filter(query, :viewed) do
    from(l in query, where: not is_nil(l.viewed_at))
  end

  def apply_link_filter(query, :all), do: query

  def apply_tag_filter(query, []), do: query

  def apply_tag_filter(query, tag_ids) do
    from(l in query,
      where:
        l.id in subquery(
          from(lt in LinkTag, where: lt.tag_id in ^tag_ids, select: lt.link_id, distinct: true)
        )
    )
  end

  def apply_sort(query, :time_added_desc) do
    from(l in query, order_by: [desc: l.inserted_at])
  end

  def apply_sort(query, :time_added_asc) do
    from(l in query, order_by: [asc: l.inserted_at])
  end

  def apply_sort(query, :expiring_soon) do
    expiry_sub =
      from(lt in LinkTag,
        group_by: lt.link_id,
        select: %{link_id: lt.link_id, max_expiry: max(lt.expires_at)}
      )

    from(l in query,
      left_join: e in subquery(expiry_sub),
      on: e.link_id == l.id,
      order_by: [asc_nulls_last: e.max_expiry]
    )
  end
end
