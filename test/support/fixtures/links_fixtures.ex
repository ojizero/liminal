defmodule Liminal.LinksFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Liminal.Links` context.
  """

  alias Liminal.Links

  def tag_fixture(scope, attrs \\ %{}) do
    {:ok, tag} =
      Links.create_tag(
        scope,
        Enum.into(attrs, %{
          name: "test-tag-#{System.unique_integer([:positive])}",
          expires_in_days: 30
        })
      )

    tag
  end

  @doc """
  Creates a link with at least one tag. A tag is created automatically
  unless `tag_ids` is provided in attrs.
  """
  def link_fixture(scope, attrs \\ %{}) do
    {tag_ids, attrs} = Map.pop(attrs, :tag_ids)

    tag_ids =
      tag_ids || [tag_fixture(scope).id]

    link_attrs =
      Enum.into(attrs, %{
        url: "https://example.com/#{System.unique_integer([:positive])}",
        title: "Test Link"
      })

    {:ok, link} = Links.create_link(scope, link_attrs, tag_ids)
    link
  end
end
