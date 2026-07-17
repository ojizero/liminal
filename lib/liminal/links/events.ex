defmodule Liminal.Links.Events do
  @moduledoc """
  PubSub topic and broadcast helpers for link changes.
  """

  @doc "Subscribe the calling process to link events for the given user."
  def subscribe_links(scope) do
    Phoenix.PubSub.subscribe(Liminal.PubSub, topic(scope.user.id))
  end

  @doc false
  def topic(user_id), do: "user_links:#{user_id}"

  @doc false
  def broadcast(user_id, message) do
    Phoenix.PubSub.broadcast(Liminal.PubSub, topic(user_id), message)
  end

  @doc false
  def broadcast_link_created(user_id, link) do
    broadcast(user_id, {:link_created, link})
  end

  @doc false
  def broadcast_link_updated(user_id, link) do
    broadcast(user_id, {:link_updated, link})
  end

  @doc false
  def broadcast_link_deleted(user_id, link_id) do
    broadcast(user_id, {:link_deleted, link_id})
  end
end
