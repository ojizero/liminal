defmodule Liminal.Links do
  @moduledoc """
  The Links context — manages links, categories, and tagging for users.
  """

  import Ecto.Query

  alias Liminal.Repo
  alias Liminal.Links.{Category, Link, LinkCategory}

  @default_categories [
    %{name: "saved for later", expires_in_days: 30},
    %{name: "read later", expires_in_days: 14},
    %{name: "watch later", expires_in_days: 30}
  ]

  ## Default categories

  @doc false
  def create_default_categories(user_id) do
    now = DateTime.utc_now(:second)

    Enum.each(@default_categories, fn %{name: name, expires_in_days: expires_in_days} ->
      Repo.insert!(
        %Category{
          name: name,
          expires_in_days: expires_in_days,
          user_id: user_id,
          inserted_at: now,
          updated_at: now
        },
        on_conflict: :nothing
      )
    end)

    :ok
  end

  ## Categories CRUD

  @doc """
  Lists all categories for the given user, ordered by name.
  """
  def list_categories(scope) do
    from(c in Category, where: c.user_id == ^scope.user.id, order_by: c.name)
    |> Repo.all()
  end

  @doc """
  Gets a single category by id, scoped to the user.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_category!(scope, id) do
    Repo.get_by!(Category, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a category for the given user.
  """
  def create_category(scope, attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, scope.user.id)
    |> Repo.insert()
  end

  @doc """
  Updates a category. Verifies ownership via pattern match.
  """
  def update_category(scope, category, attrs) do
    user_id = scope.user.id
    ^user_id = category.user_id

    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category. Verifies ownership via pattern match.
  """
  def delete_category(scope, category) do
    user_id = scope.user.id
    ^user_id = category.user_id

    Repo.delete(category)
  end

  @doc """
  Returns a changeset for tracking category changes.
  """
  def change_category(category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  ## Links CRUD

  @doc """
  Lists links for the given user with preloaded categories.

  ## Options

    * `:filter` - `:unviewed` (default), `:all`, or `:viewed`

  """
  def list_links(scope, opts \\ []) do
    filter = Keyword.get(opts, :filter, :unviewed)

    from(l in Link, where: l.user_id == ^scope.user.id, order_by: [desc: l.inserted_at])
    |> apply_link_filter(filter)
    |> Repo.all()
    |> Repo.preload(link_categories: :category)
  end

  defp apply_link_filter(query, :unviewed) do
    from(l in query, where: is_nil(l.viewed_at))
  end

  defp apply_link_filter(query, :viewed) do
    from(l in query, where: not is_nil(l.viewed_at))
  end

  defp apply_link_filter(query, :all), do: query

  @doc """
  Gets a single link by id, scoped to the user, with preloaded categories.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_link!(scope, id) do
    Repo.get_by!(Link, id: id, user_id: scope.user.id)
    |> Repo.preload(link_categories: :category)
  end

  @doc """
  Creates a link for the given user.
  """
  def create_link(scope, attrs) do
    %Link{}
    |> Link.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, scope.user.id)
    |> Repo.insert()
  end

  @doc """
  Updates a link. Verifies ownership via pattern match.
  """
  def update_link(scope, link, attrs) do
    user_id = scope.user.id
    ^user_id = link.user_id

    link
    |> Link.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a link. Verifies ownership via pattern match.
  """
  def delete_link(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    Repo.delete(link)
  end

  @doc """
  Returns a changeset for tracking link changes.
  """
  def change_link(link, attrs \\ %{}) do
    Link.changeset(link, attrs)
  end

  ## Viewed state

  @doc """
  Marks a link as viewed with the current timestamp.
  """
  def mark_viewed(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    link
    |> Ecto.Changeset.change(viewed_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  @doc """
  Marks a link as unviewed by clearing the viewed_at timestamp.
  """
  def mark_unviewed(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    link
    |> Ecto.Changeset.change(viewed_at: nil)
    |> Repo.update()
  end

  ## Tagging

  @doc """
  Tags a link with a category. Computes `expires_at` from the category's
  `expires_in_days`. Uses `on_conflict: :nothing` for idempotency.
  """
  def tag_link(scope, link, category) do
    user_id = scope.user.id
    ^user_id = link.user_id
    ^user_id = category.user_id

    expires_at =
      if category.expires_in_days do
        DateTime.utc_now(:second) |> DateTime.add(category.expires_in_days, :day)
      end

    now = DateTime.utc_now(:second)

    Repo.insert(
      %LinkCategory{
        link_id: link.id,
        category_id: category.id,
        expires_at: expires_at,
        inserted_at: now
      },
      on_conflict: :nothing
    )
  end

  @doc """
  Removes a category tag from a link.
  """
  def untag_link(scope, link, category) do
    user_id = scope.user.id
    ^user_id = link.user_id
    ^user_id = category.user_id

    link_category = Repo.get_by!(LinkCategory, link_id: link.id, category_id: category.id)
    Repo.delete(link_category)
  end
end
