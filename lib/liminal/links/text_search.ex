defmodule Liminal.Links.TextSearch do
  @moduledoc """
  Fuzzy text search for links across title, note, description, and URL.

  Supports typo-tolerant matching by comparing query terms against normalized
  field text and tokenized words using Levenshtein distance.
  """

  alias Liminal.Links.Link

  @searchable_fields [:title, :note, :description, :url]

  @doc """
  Returns whether a link matches the given search query.

  Blank or whitespace-only queries match every link.
  """
  def matches?(%Link{} = link, query) when is_binary(query) do
    normalized_query = normalize(query)

    if normalized_query == "" do
      true
    else
      haystack = searchable_text(link)
      terms = String.split(normalized_query, ~r/\s+/, trim: true)
      Enum.all?(terms, &term_matches?(&1, haystack))
    end
  end

  @doc """
  Filters links to those matching the query.
  """
  def filter_links(links, query) when is_list(links) and is_binary(query) do
    normalized_query = normalize(query)

    if normalized_query == "" do
      links
    else
      Enum.filter(links, &matches?(&1, query))
    end
  end

  defp searchable_text(%Link{} = link) do
    @searchable_fields
    |> Enum.map(fn field -> Map.get(link, field) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> normalize()
  end

  defp normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp term_matches?(term, haystack) do
    cond do
      String.contains?(haystack, term) ->
        true

      String.length(term) <= 2 ->
        false

      true ->
        tokens = tokenize(haystack)
        max_edits = max_edits_for(term)
        Enum.any?(tokens, fn token -> levenshtein(token, term) <= max_edits end)
    end
  end

  defp tokenize(text) do
    text
    |> String.split(~r/[^a-z0-9]+/u, trim: true)
    |> Enum.reject(&(String.length(&1) <= 1))
  end

  defp max_edits_for(term) do
    case String.length(term) do
      len when len <= 4 -> 1
      len when len <= 7 -> 2
      len -> max(2, div(len, 4))
    end
  end

  defp levenshtein(left, right) do
    left_chars = String.graphemes(left)
    right_chars = String.graphemes(right)

    for i <- 0..length(left_chars), reduce: %{} do
      matrix ->
        for j <- 0..length(right_chars), reduce: matrix do
          matrix ->
            value =
              cond do
                i == 0 ->
                  j

                j == 0 ->
                  i

                true ->
                  cost =
                    if Enum.at(left_chars, i - 1) == Enum.at(right_chars, j - 1),
                      do: 0,
                      else: 1

                  min3(
                    Map.fetch!(matrix, {i - 1, j}) + 1,
                    Map.fetch!(matrix, {i, j - 1}) + 1,
                    Map.fetch!(matrix, {i - 1, j - 1}) + cost
                  )
              end

            Map.put(matrix, {i, j}, value)
        end
    end
    |> Map.fetch!({length(left_chars), length(right_chars)})
  end

  defp min3(a, b, c), do: a |> min(b) |> min(c)
end
