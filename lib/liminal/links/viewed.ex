defmodule Liminal.Links.Viewed do
  @moduledoc """
  Viewed state mutations for links.
  """

  alias Liminal.Links.Events
  alias Liminal.Repo

  @doc "Marks a link as viewed now."
  def mark_viewed(scope, link) do
    update_viewed_at(scope, link, DateTime.utc_now(:second))
  end

  @doc "Clears the viewed timestamp on a link."
  def mark_unviewed(scope, link) do
    update_viewed_at(scope, link, nil)
  end

  defp update_viewed_at(scope, link, viewed_at) do
    user_id = scope.user.id
    ^user_id = link.user_id

    link
    |> Ecto.Changeset.change(viewed_at: viewed_at)
    |> Repo.update()
    |> case do
      {:ok, updated_link} ->
        updated_link = Repo.preload(updated_link, [link_tags: :tag], force: true)
        Events.broadcast_link_updated(user_id, updated_link)
        {:ok, updated_link}

      error ->
        error
    end
  end
end
