defmodule Liminal.Links.Viewed do
  @moduledoc """
  Viewed state mutations for links.
  """

  alias Liminal.Links.Events
  alias Liminal.Links.ExpiryPause
  alias Liminal.Repo

  @doc """
  Marks a link as viewed now.

  The timestamp is written on the expiry clock, so a link viewed during a pause
  keeps its full grace period once expiries resume.
  """
  def mark_viewed(scope, link) do
    update_viewed_at(scope, link, ExpiryPause.expiry_now(scope.user.id))
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
