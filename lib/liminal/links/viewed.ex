defmodule Liminal.Links.Viewed do
  @moduledoc """
  Commands for toggling a link's viewed state.
  """

  alias Liminal.Links.PubSub
  alias Liminal.Repo

  @doc "Marks a link as viewed now."
  def mark_viewed(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    persist_viewed_change(user_id, link, viewed_at: DateTime.utc_now(:second))
  end

  @doc "Clears the viewed timestamp on a link."
  def mark_unviewed(scope, link) do
    user_id = scope.user.id
    ^user_id = link.user_id

    persist_viewed_change(user_id, link, viewed_at: nil)
  end

  defp persist_viewed_change(user_id, link, attrs) do
    case link |> Ecto.Changeset.change(attrs) |> Repo.update() do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        PubSub.broadcast(user_id, {:link_updated, updated_link})
        {:ok, updated_link}

      error ->
        error
    end
  end
end
