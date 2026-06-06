defmodule Liminal.Links.TextSearchTest do
  use Liminal.DataCase, async: true

  alias Liminal.Links.TextSearch
  alias Liminal.Links.Link

  defp link(attrs) do
    struct!(
      Link,
      Enum.into(attrs, %{
        url: "https://example.com/articles/elixir-programming",
        title: "Elixir Programming Guide",
        note: "Read this before the conference",
        description: "A comprehensive introduction to functional programming in Elixir."
      })
    )
  end

  describe "matches?/2" do
    test "blank query matches everything" do
      assert TextSearch.matches?(link(%{}), "")
      assert TextSearch.matches?(link(%{}), "   ")
    end

    test "matches title exactly" do
      assert TextSearch.matches?(link(%{}), "elixir programming")
    end

    test "matches note" do
      assert TextSearch.matches?(link(%{}), "conference")
    end

    test "matches description" do
      assert TextSearch.matches?(link(%{}), "functional programming")
    end

    test "matches url" do
      assert TextSearch.matches?(link(%{}), "example.com/articles")
    end

    test "allows typos in title" do
      assert TextSearch.matches?(link(%{}), "elxir programing")
    end

    test "allows typos in note" do
      assert TextSearch.matches?(link(%{}), "conferance")
    end

    test "requires all terms to match" do
      refute TextSearch.matches?(link(%{}), "elixir phoenix")
    end

    test "ignores nil fields" do
      link = link(%{note: nil, description: nil, title: nil})

      assert TextSearch.matches?(link, "example.com")
      refute TextSearch.matches?(link, "missing")
    end
  end

  describe "filter_links/2" do
    test "returns all links for blank query" do
      links = [link(%{title: "One"}), link(%{title: "Two"})]
      assert length(TextSearch.filter_links(links, "")) == 2
    end

    test "filters links by query" do
      matching = link(%{title: "Phoenix LiveView"})
      other = link(%{title: "Something else"})

      results = TextSearch.filter_links([matching, other], "liveveiw")
      assert results == [matching]
    end
  end
end
