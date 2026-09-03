defmodule Liminal.LinksFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Liminal.Links` context.
  """

  import Ecto.Query

  alias Liminal.Accounts
  alias Liminal.Links
  alias Liminal.Links.LinkTag
  alias Liminal.Repo

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

  @doc """
  Rewinds a user's pause window by `seconds` so that much wall time appears to have
  passed since it started, and returns the reloaded user.

  Both ends move together, so a pause aged past its own length reads as lapsed.
  """
  def age_expiry_pause(user, seconds) do
    Repo.update_all(
      from(u in Accounts.User, where: u.id == ^user.id),
      set: [
        expiry_paused_at: DateTime.add(user.expiry_paused_at, -seconds, :second),
        expiry_paused_until: DateTime.add(user.expiry_paused_until, -seconds, :second)
      ]
    )

    Accounts.get_user!(user.id)
  end

  @doc """
  Ends a user's pause window in the past without settling it, as if the sweep had
  not run since, and returns the reloaded user.
  """
  def lapse_expiry_pause(user, seconds_ago \\ 1) do
    Repo.update_all(
      from(u in Accounts.User, where: u.id == ^user.id),
      set: [expiry_paused_until: DateTime.add(DateTime.utc_now(:second), -seconds_ago, :second)]
    )

    Accounts.get_user!(user.id)
  end

  @doc "Forces a link's tag deadlines to `expires_at`."
  def set_link_tag_expiry(link, expires_at) do
    Repo.update_all(
      from(lt in LinkTag, where: lt.link_id == ^link.id),
      set: [expires_at: expires_at]
    )

    :ok
  end

  @doc "Returns a link's tag deadlines, earliest first."
  def link_tag_expiries(link) do
    from(lt in LinkTag, where: lt.link_id == ^link.id, order_by: lt.expires_at)
    |> Repo.all()
    |> Enum.map(& &1.expires_at)
  end
end
