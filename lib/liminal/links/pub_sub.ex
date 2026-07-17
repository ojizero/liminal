defmodule Liminal.Links.PubSub do
  @moduledoc """
  PubSub topics and broadcasts for link changes.
  """

  @doc "Subscribe the calling process to link events for the given user."
  def subscribe_links(scope) do
    Phoenix.PubSub.subscribe(Liminal.PubSub, topic(scope.user.id))
  end

  def topic(user_id), do: "user_links:#{user_id}"

  def broadcast(user_id, message) do
    Phoenix.PubSub.broadcast(Liminal.PubSub, topic(user_id), message)
  end

  def broadcast_link_deleted(user_id, link_id) do
    broadcast(user_id, {:link_deleted, link_id})
  end
end
