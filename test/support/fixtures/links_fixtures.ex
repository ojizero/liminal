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

  def link_fixture(scope, attrs \\ %{}) do
    {:ok, link} =
      Links.create_link(
        scope,
        Enum.into(attrs, %{
          url: "https://example.com/#{System.unique_integer([:positive])}",
          title: "Test Link"
        })
      )

    link
  end
end
