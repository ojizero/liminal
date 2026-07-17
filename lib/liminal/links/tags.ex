defmodule Liminal.Links.Tags do
  @moduledoc """
  Tag defaults and CRUD operations scoped to a user.
  """

  import Ecto.Query

  alias Liminal.Links.Tag
  alias Liminal.Repo

  @default_tags [
    %{name: "saved for later", expires_in_days: 30},
    %{name: "read later", expires_in_days: 14},
    %{name: "watch later", expires_in_days: 30}
  ]

  @doc "Creates default tags for a new user."
  def create_default_tags(user_id) do
    now = DateTime.utc_now(:second)

    Enum.each(@default_tags, fn %{name: name, expires_in_days: expires_in_days} ->
      Repo.insert!(
        %Tag{
          name: name,
          expires_in_days: expires_in_days,
          user_id: user_id,
          inserted_at: now,
          updated_at: now
        },
        on_conflict: :nothing
      )
    end)

    :ok
  end

  @doc "Lists all tags for the given user, ordered by name."
  def list_tags(scope) do
    from(t in Tag, where: t.user_id == ^scope.user.id, order_by: t.name)
    |> Repo.all()
  end

  @doc "Gets a single tag by id, scoped to the user."
  def get_tag!(scope, id) do
    Repo.get_by!(Tag, id: id, user_id: scope.user.id)
  end

  @doc "Creates a tag for the given user."
  def create_tag(scope, attrs) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, scope.user.id)
    |> Repo.insert()
  end

  @doc "Updates a tag. Verifies ownership via pattern match."
  def update_tag(scope, tag, attrs) do
    user_id = scope.user.id
    ^user_id = tag.user_id

    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a tag. Verifies ownership via pattern match."
  def delete_tag(scope, tag) do
    user_id = scope.user.id
    ^user_id = tag.user_id

    Repo.delete(tag)
  end

  @doc "Returns a changeset for tracking tag changes."
  def change_tag(tag, attrs \\ %{}) do
    Tag.changeset(tag, attrs)
  end
end
