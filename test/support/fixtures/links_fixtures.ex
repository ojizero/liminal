defmodule Liminal.LinksFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Liminal.Links` context.
  """

  alias Liminal.Links

  def category_fixture(scope, attrs \\ %{}) do
    {:ok, category} =
      Links.create_category(
        scope,
        Enum.into(attrs, %{
          name: "test-cat-#{System.unique_integer([:positive])}",
          expires_in_days: 30
        })
      )

    category
  end

  @doc """
  Creates a link with at least one category. A category is created automatically
  unless `category_ids` is provided in attrs.
  """
  def link_fixture(scope, attrs \\ %{}) do
    {category_ids, attrs} = Map.pop(attrs, :category_ids)

    category_ids =
      category_ids || [category_fixture(scope).id]

    link_attrs =
      Enum.into(attrs, %{
        url: "https://example.com/#{System.unique_integer([:positive])}",
        title: "Test Link"
      })

    {:ok, link} = Links.create_link(scope, link_attrs, category_ids)
    link
  end
end
